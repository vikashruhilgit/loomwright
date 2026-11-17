// runner/trace-redact.mjs — strips secrets from a Playwright trace zip before `run --trace` keeps it.
//
// redactTraceZip(inFile, outFile, { secrets, values }) reads the zip Playwright wrote, redacts every entry
// that decodes as UTF-8 text (trace.trace, trace.network, trace.stacks, resources/*), and writes
// outFile (a temp name, then a rename). → { kept: true, entries } or { kept: false, why }: a zip it
// cannot read whole — zip64, encryption, a compression method other than stored / deflate, a CRC or
// size that does not match, a truncated file — is never written out, and neither is one whose binary
// entries still hold a secret. It never deletes inFile; the caller does, kept or not.
//
// What is redacted, in every text entry:
//   1. the value of every Cookie, Set-Cookie and Authorization header becomes "[redacted]" — a HAR
//      header object {name, value}, a header-map key ({"cookie": "…"}) in a JSON line, or a
//      `Name: value` line in raw text
//   2. every cookie value seen in any Cookie / Set-Cookie header (or HAR `cookies` entry) of the
//      whole trace, and every Authorization value (whole, and its credentials after the scheme), is
//      replaced by "[redacted]" wherever it appears — in a page's HTML, a script, a snapshot
//   3. every resolved {{NAME}} value of the run goes back to {{NAME}} (redactValues, snapshot.mjs)
//   4. a `storageState` key's whole value becomes "[redacted]" (the context-options event records the
//      context's storage state), and every value in a `cookies` or `localStorage` list of
//      { name, value } — and every value passed in `values` (the stored session's, execute.mjs) — is
//      replaced by "[redacted]" wherever it appears, as in 2
// JSON lines are parsed and redacted string by string (so they stay valid JSON); other text is
// redacted as text. Binary entries (images) are copied, and the whole trace is dropped when one
// holds a secret's bytes. A value the page shows transformed (cut, reversed) is not caught — the
// same limit as redactValues; `run` starts tracing without screenshots, since an image of a typed
// value cannot be redacted.
//
// The zip format is read by hand on node:zlib (inflateRawSync), so nothing beyond Node >= 18 is
// needed: the output is written with every entry "stored" (method 0) and a table CRC-32
// (zlib.crc32 is only in Node >= 20.15).
//
// Node >= 18, standard library only.
import { renameSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { inflateRawSync } from 'node:zlib';
import { encodedForms, redactValues } from '../snapshot.mjs';

export const REDACTED = '[redacted]';
// Header names (lower case) whose values are never kept.
export const REDACTED_HEADERS = Object.freeze(['cookie', 'set-cookie', 'authorization']);
const COOKIE_HEADERS = Object.freeze(['cookie', 'set-cookie']);
// Keys whose array holds { name, value } entries whose every value is a secret (HAR / storage-state
// cookies, a storage state's origins[].localStorage).
const VALUE_LISTS = Object.freeze(['cookies', 'localStorage']);
// Keys whose whole value is replaced by REDACTED: the context's storage state, which Playwright
// records in the trace's context-options event.
export const REDACTED_KEYS = Object.freeze(['storageState']);

const SIG = Object.freeze({ local: 0x04034b50, central: 0x02014b50, end: 0x06054b50, end64Locator: 0x07064b50 });
const METHOD = Object.freeze({ stored: 0, deflate: 8 });
const FLAG = Object.freeze({ encrypted: 0x0001, utf8: 0x0800 });
const MAX16 = 0xffff;
const MAX32 = 0xffffffff;
const ZIP64_EXTRA = 0x0001;

class TraceZipError extends Error {}

// ---- CRC-32 (IEEE, the zip polynomial) ----------------------------------------------------------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i += 1) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

// ---- reader -------------------------------------------------------------------------------------
function hasZip64Extra(extra) {
  for (let i = 0; i + 4 <= extra.length;) {
    const id = extra.readUInt16LE(i);
    const size = extra.readUInt16LE(i + 2);
    if (id === ZIP64_EXTRA) return true;
    i += 4 + size;
  }
  return false;
}

// readZip(buf) → [{ name, nameBytes, flags, time, date, data }] (data uncompressed and CRC-checked).
// Throws TraceZipError naming why when the zip is anything this reader does not handle whole.
export function readZip(buf) {
  const fail = (why) => {
    throw new TraceZipError(why);
  };
  if (buf.length < 22) fail('not a zip (too short)');
  let end = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - MAX16); i -= 1) {
    if (buf.readUInt32LE(i) === SIG.end) {
      end = i;
      break;
    }
  }
  if (end < 0) fail('not a zip (no end of central directory)');
  if (end >= 20 && buf.readUInt32LE(end - 20) === SIG.end64Locator) fail('zip64');
  if (buf.readUInt16LE(end + 4) !== 0 || buf.readUInt16LE(end + 6) !== 0) fail('a multi-disk zip');
  const count = buf.readUInt16LE(end + 10);
  const cdSize = buf.readUInt32LE(end + 12);
  const cdOffset = buf.readUInt32LE(end + 16);
  if (count === MAX16 || cdSize === MAX32 || cdOffset === MAX32) fail('zip64');
  if (cdOffset + cdSize > end) fail('a central directory past its end record');

  const entries = [];
  let p = cdOffset;
  for (let n = 0; n < count; n += 1) {
    if (p + 46 > end || buf.readUInt32LE(p) !== SIG.central) fail(`a bad central directory entry (#${n + 1})`);
    const flags = buf.readUInt16LE(p + 8);
    const method = buf.readUInt16LE(p + 10);
    const time = buf.readUInt16LE(p + 12);
    const date = buf.readUInt16LE(p + 14);
    const crc = buf.readUInt32LE(p + 16);
    const compSize = buf.readUInt32LE(p + 20);
    const size = buf.readUInt32LE(p + 24);
    const nameLen = buf.readUInt16LE(p + 28);
    const extraLen = buf.readUInt16LE(p + 30);
    const commentLen = buf.readUInt16LE(p + 32);
    const localOffset = buf.readUInt32LE(p + 42);
    const nameBytes = buf.subarray(p + 46, p + 46 + nameLen);
    const name = nameBytes.toString('utf8');
    const extra = buf.subarray(p + 46 + nameLen, p + 46 + nameLen + extraLen);
    p += 46 + nameLen + extraLen + commentLen;
    if (p > end) fail(`a central directory entry past its end (${name})`);
    if (flags & FLAG.encrypted) fail(`an encrypted entry (${name})`);
    if (compSize === MAX32 || size === MAX32 || localOffset === MAX32 || hasZip64Extra(extra)) fail(`zip64 (${name})`);
    if (method !== METHOD.stored && method !== METHOD.deflate) fail(`compression method ${method} (${name})`);

    if (localOffset + 30 > cdOffset || buf.readUInt32LE(localOffset) !== SIG.local) fail(`a bad local header (${name})`);
    const start = localOffset + 30 + buf.readUInt16LE(localOffset + 26) + buf.readUInt16LE(localOffset + 28);
    if (start + compSize > cdOffset) fail(`entry data past the central directory (${name})`);
    const raw = buf.subarray(start, start + compSize);
    let data;
    if (method === METHOD.stored) data = Buffer.from(raw);
    else {
      try {
        data = inflateRawSync(raw);
      } catch (e) {
        fail(`an entry that does not inflate (${name}: ${e && e.code ? e.code : 'error'})`);
      }
    }
    if (data.length !== size || crc32(data) !== crc) fail(`a size or CRC-32 mismatch (${name})`);
    entries.push({ name, nameBytes: Buffer.from(nameBytes), flags: flags & FLAG.utf8, time, date, data });
  }
  return entries;
}

// ---- writer -------------------------------------------------------------------------------------
// writeZip(entries) → Buffer: every entry stored (method 0), no data descriptors, no zip64.
export function writeZip(entries) {
  if (entries.length >= MAX16) throw new TraceZipError('too many entries for a zip without zip64');
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const e of entries) {
    const crc = crc32(e.data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(SIG.local, 0);
    local.writeUInt16LE(20, 4); // version needed: 2.0
    local.writeUInt16LE(e.flags, 6);
    local.writeUInt16LE(METHOD.stored, 8);
    local.writeUInt16LE(e.time, 10);
    local.writeUInt16LE(e.date, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(e.data.length, 18);
    local.writeUInt32LE(e.data.length, 22);
    local.writeUInt16LE(e.nameBytes.length, 26);
    local.writeUInt16LE(0, 28);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(SIG.central, 0);
    central.writeUInt16LE(20, 4); // made by: 2.0
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(e.flags, 8);
    central.writeUInt16LE(METHOD.stored, 10);
    central.writeUInt16LE(e.time, 12);
    central.writeUInt16LE(e.date, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(e.data.length, 20);
    central.writeUInt32LE(e.data.length, 24);
    central.writeUInt16LE(e.nameBytes.length, 28);
    central.writeUInt32LE(offset, 42);
    locals.push(local, e.nameBytes, e.data);
    centrals.push(central, e.nameBytes);
    offset += 30 + e.nameBytes.length + e.data.length;
    if (offset >= MAX32) throw new TraceZipError('too large for a zip without zip64');
  }
  const cd = Buffer.concat(centrals);
  const endRec = Buffer.alloc(22);
  endRec.writeUInt32LE(SIG.end, 0);
  endRec.writeUInt16LE(entries.length, 8);
  endRec.writeUInt16LE(entries.length, 10);
  endRec.writeUInt32LE(cd.length, 12);
  endRec.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, cd, endRec]);
}

// ---- redaction ----------------------------------------------------------------------------------
const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);
const decoder = new TextDecoder('utf-8', { fatal: true });
const RAW_HEADER_LINE = new RegExp(`^([ \\t]*(?:${REDACTED_HEADERS.join('|')})[ \\t]*:[ \\t]*)(.*)$`, 'gim');
const RAW_JSON_HEADER = new RegExp(`("(?:${REDACTED_HEADERS.join('|')})"\\s*:\\s*)"((?:[^"\\\\]|\\\\.)*)"`, 'gi');

const isRedactedHeader = (name) => typeof name === 'string' && REDACTED_HEADERS.includes(name.toLowerCase());
const isCookieHeader = (name) => typeof name === 'string' && COOKIE_HEADERS.includes(name.toLowerCase());

function unquote(v) {
  const t = v.trim();
  return t.length >= 2 && t.startsWith('"') && t.endsWith('"') ? t.slice(1, -1) : t;
}

// The secret values one header value carries (added to `into`).
function collectHeader(name, value, into) {
  if (typeof value !== 'string' || value === '') return;
  const lower = name.toLowerCase();
  if (lower === 'authorization') {
    into.add(value.trim());
    const sp = value.trim().indexOf(' ');
    if (sp > 0) into.add(value.trim().slice(sp + 1).trim());
    return;
  }
  // Cookie: every `name=value` pair; Set-Cookie: one cookie per line, its first pair only (the
  // rest are attributes such as Path=/).
  const pairs = lower === 'cookie' ? value.split(';') : value.split('\n').map((l) => l.split(';')[0]);
  for (const pair of pairs) {
    const eq = pair.indexOf('=');
    if (eq < 0) continue;
    const v = unquote(pair.slice(eq + 1));
    if (v === '') continue;
    into.add(v);
    try {
      const decoded = decodeURIComponent(v);
      if (decoded !== '') into.add(decoded);
    } catch {
      // not percent-encoded
    }
  }
}

// Walks a parsed JSON value, collecting secret values from headers, HAR cookie entries and a storage
// state's cookies and localStorage entries.
function collectJson(v, into, key = null) {
  if (Array.isArray(v)) {
    for (const x of v) {
      if (VALUE_LISTS.includes(key) && isPlainObject(x) && typeof x.value === 'string' && x.value !== '') into.add(x.value);
      collectJson(x, into);
    }
    return;
  }
  if (!isPlainObject(v)) return;
  if (isRedactedHeader(v.name) && typeof v.value === 'string') collectHeader(v.name, v.value, into);
  for (const [k, x] of Object.entries(v)) {
    if (isRedactedHeader(k) && typeof x === 'string') collectHeader(k, x, into);
    collectJson(x, into, k);
  }
}

// Escapes a string for a RegExp alternation.
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

// The replacer for the collected values (longest first, one pass), or the identity.
function valueReplacer(values) {
  const list = [...values].filter((v) => v !== '' && v !== REDACTED).sort((a, b) => b.length - a.length);
  if (!list.length) return (s) => s;
  const re = new RegExp(list.map(escapeRe).join('|'), 'g');
  return (s) => s.replace(re, REDACTED);
}

// secrets carries `forms` (every encodedForms() form of every value) so the common string that holds
// none skips redactValues, which compiles its pattern on each call.
function redactString(s, replaceValues, secrets) {
  const t = replaceValues(s);
  return secrets.forms.some((f) => t.includes(f)) ? redactValues(t, secrets) : t;
}

// A parsed JSON value with header values set to REDACTED and every string (and key) redacted.
function redactJson(v, replaceValues, secrets) {
  if (typeof v === 'string') return redactString(v, replaceValues, secrets);
  if (Array.isArray(v)) return v.map((x) => redactJson(x, replaceValues, secrets));
  if (!isPlainObject(v)) return v;
  const headerObject = isRedactedHeader(v.name) && typeof v.value === 'string';
  const out = {};
  for (const [k, x] of Object.entries(v)) {
    const key = redactString(k, replaceValues, secrets);
    if ((headerObject && k === 'value') || (isRedactedHeader(k) && typeof x === 'string') || (REDACTED_KEYS.includes(k) && x !== null && x !== undefined)) out[key] = REDACTED;
    else out[key] = redactJson(x, replaceValues, secrets);
  }
  return out;
}

function parseJsonLine(line) {
  const t = line.trim();
  if (!(t.startsWith('{') || t.startsWith('['))) return undefined;
  try {
    return JSON.parse(t);
  } catch {
    return undefined;
  }
}

function collectRaw(line, into) {
  for (const m of line.matchAll(RAW_HEADER_LINE)) collectHeader(m[1].replace(/[\s:]/g, ''), m[2], into);
  for (const m of line.matchAll(RAW_JSON_HEADER)) {
    let value = m[2];
    try {
      value = JSON.parse(`"${m[2]}"`);
    } catch {
      // keep the escaped form
    }
    collectHeader(m[1].replace(/["\s:]/g, ''), value, into);
  }
}

function redactRaw(line, replaceValues, secrets) {
  const headersGone = line.replace(RAW_HEADER_LINE, (_m, head) => `${head}${REDACTED}`).replace(RAW_JSON_HEADER, (_m, head) => `${head}"${REDACTED}"`);
  return redactString(headersGone, replaceValues, secrets);
}

// redactEntries(entries, secrets, values) → { entries, leaked: null | entry name }. Pure: no file
// access. `values` are raw strings redacted as cookie values are (the stored session's, known before
// the trace is read).
export function redactEntries(entries, secretList = [], extraValues = []) {
  const secrets = Object.assign([...secretList], { forms: secretList.flatMap((s) => encodedForms(s.value)) });
  const texts = entries.map((e) => {
    try {
      return decoder.decode(e.data);
    } catch {
      return null; // binary
    }
  });
  // pass 1: every cookie and Authorization value in the whole trace
  const values = new Set(extraValues.filter((v) => typeof v === 'string' && v !== ''));
  for (const text of texts) {
    if (text === null) continue;
    for (const line of text.split('\n')) {
      const parsed = parseJsonLine(line);
      if (parsed !== undefined) collectJson(parsed, values);
      else collectRaw(line, values);
    }
  }
  const replaceValues = valueReplacer(values);
  // pass 2: redact every text entry
  const out = entries.map((e, i) => {
    const text = texts[i];
    if (text === null) return e;
    const lines = text.split('\n').map((line) => {
      const parsed = parseJsonLine(line);
      return parsed !== undefined ? JSON.stringify(redactJson(parsed, replaceValues, secrets)) : redactRaw(line, replaceValues, secrets);
    });
    return { ...e, data: Buffer.from(lines.join('\n'), 'utf8') };
  });
  // a binary entry that still holds a secret's bytes drops the whole trace (fail closed)
  const needles = [...values, ...secrets.map((s) => s.value)].filter((v) => typeof v === 'string' && v !== '' && v !== REDACTED).map((v) => Buffer.from(v, 'utf8'));
  for (let i = 0; i < out.length; i += 1) {
    if (texts[i] !== null) continue;
    if (needles.some((n) => out[i].data.includes(n))) return { entries: out, leaked: out[i].name };
  }
  return { entries: out, leaked: null };
}

// redactTraceZip(inFile, outFile, { secrets, values }) → { kept: true, entries } | { kept: false, why }
export function redactTraceZip(inFile, outFile, { secrets = [], values = [] } = {}) {
  let entries;
  try {
    entries = readZip(readFileSync(inFile));
  } catch (e) {
    if (e instanceof TraceZipError) return { kept: false, why: e.message };
    return { kept: false, why: `unreadable (${e && e.code ? e.code : e && e.message})` };
  }
  const red = redactEntries(entries, secrets, values);
  if (red.leaked !== null) return { kept: false, why: `a binary entry holds a secret value (${red.leaked})` };
  const tmp = `${outFile}.tmp-${process.pid}`;
  try {
    writeFileSync(tmp, writeZip(red.entries), { mode: 0o600 });
    renameSync(tmp, outFile);
  } catch (e) {
    rmSync(tmp, { force: true });
    return { kept: false, why: e instanceof TraceZipError ? e.message : `not written (${e && e.code ? e.code : e && e.message})` };
  }
  return { kept: true, entries: red.entries.length };
}
