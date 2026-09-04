/* floor.js - renders .supervisor/floor/floor.json into The Floor.
 *
 * THE ONE RULE THIS FILE EXISTS TO ENFORCE: nothing moves that is not backed by a recorded
 * event. There is exactly ONE timer in this file (the poll below) and it fetches; it does not
 * animate. The only moving element is a lane's shuttle, and it advances only when THAT lane's
 * `events` count differs from the previous render. A lane whose count did not change does not
 * move, and a page that is fetching the same bytes over and over is visually still.
 * The single stated exemption is the `.pulse` keyframe in floor.css, which is applied only to
 * a NON-stalled lane - its absence is the stall signal, so its presence is state-driven.
 * (There is deliberately no rAF loop and no second timer here; the self-test counts.)
 *
 * ABSENT EVIDENCE IS RENDERED AS UNKNOWN, NEVER AS ZERO. floor.json omits `count` entirely
 * for a surface it could not count, and this file renders that as an em dash with the
 * projector's own `reason` as the cell title. It never substitutes 0, and it never infers a
 * value the projector refused to state. `read_only` on a roster row is a TRI-STATE for the
 * same reason - true / false / absent - and absent renders as "read-only unknown".
 * THE SAME RULE GOVERNS THE BANNER: an empty lane list is not by itself evidence that nothing
 * is running, because the projector omits `sessions.detail.current` whenever no log line
 * carries a `ts` and reports the surface `unverified` when a log could not be read. Only a
 * counted surface carrying a `current` view with zero agents earns the idle claim; every
 * other shape says the session data is unavailable and quotes the projector's own reason.
 *
 * LIVENESS IS NEVER INFERRED. floor.json records events, not processes. No element on this
 * page is labelled with a word that would claim a running process; the permanent note under
 * the lanes says so on every render, and the self-test scans for those words by name.
 *
 * NETWORK: relative requests against this page's own origin and nothing else. There are exactly
 * TWO `fetch(` call sites in this file - the READ helper `fetchText` and the WRITE helper
 * `postAction` - and every URL handed to either is built HERE from a fixed string, never taken
 * verbatim from a document the page just read. Two documents are read per tick (`index.json`,
 * then the selected project's `floor.json`) and they are CHAINED, never concurrent: the poll
 * holds one in-flight flag across both, so a hung origin cannot stack requests, and the flag is
 * cleared on every settle path.
 *
 * THE PICKER STILL SENDS NOTHING. Selecting a project switches which already-written document
 * this page DISPLAYS. It asks for nothing the server does not already hold as a file, and
 * cannot cause a regeneration: which project the serve loop regenerates on the fast cadence is
 * decided by the engine, from the directory `serve` was launched in. So a project on the slow
 * cadence reads as exactly that - its own recorded age, next to the cadence the served index
 * states - rather than as a fresh floor.
 *
 * THE FOUR BUTTONS THAT DO SEND SOMETHING, AND WHY THEY ARE GUARDED. `add`, `forget`, `scan`
 * and `stop` are the only writes this page can reach, and each one is a real write, so a
 * loopback port is not enough: any site open in another tab can `fetch` a POST at
 * 127.0.0.1:<port> and never read the reply, and the write has still landed. Every mutating
 * request therefore carries this run's token in a CUSTOM header, which is what forces a CORS
 * preflight the other tab cannot satisfy; the server checks that token, the `Origin` and the
 * `Host` besides. The token is read ONCE, out of the URL fragment `serve` printed - a fragment
 * is never sent to any server - and stripped from the address bar immediately, so it cannot
 * leak through history, a bookmark or a shared screenshot.
 *
 * NO NEW TIMER, NOT EVEN FOR THE WRITE PATH. There is still exactly one timer on this page.
 * A write is followed by an immediate re-poll of the ONE existing loop, never by a retry
 * schedule, a debounce or a "saved" flash - all three of which are timers wearing a hat, and
 * all three would break the rule at the top of this file.
 */
'use strict';

(function () {
  var POLL_MS = 2000;

  /* Query parameters, all optional, all integers, all clamped to something sane.
   *   ?stall=<seconds>  how old a lane's last event may get before the lane reads stalled
   *   ?stale=<seconds>  how old floor.json itself may get before the page says so. It exists
   *                     so the committed fixtures (whose generated_at_epoch is necessarily in
   *                     the past) can be demonstrated without the stale banner swallowing the
   *                     view; the default is 3x THIS PAGE'S OWN poll interval below.
   *                     That default is NOT the serve loop's `--interval`, which this page has
   *                     no way to observe: `setup-ui.sh serve --interval 10` regenerates every
   *                     10 s, which is legal and documented, and every render of it is older
   *                     than a 6 s default. So the banner states the age and the threshold it
   *                     was measured against and stops there - it never claims a cause it
   *                     cannot see - and `serve` prints the `?stale=` value to open the page
   *                     with whenever its own interval outgrows this default.
   */
  function qpInt(name, dflt, lo) {
    var m = new RegExp('[?&]' + name + '=([0-9]+)').exec(window.location.search || '');
    if (!m) { return dflt; }
    var n = parseInt(m[1], 10);
    if (!isFinite(n) || n < lo) { return dflt; }
    return n;
  }
  var STALL_SEC = qpInt('stall', 300, 1);
  var STALE_SEC = qpInt('stale', Math.round((POLL_MS / 1000) * 3), 1);

  var el = function (id) { return document.getElementById(id); };

  /* Per-lane memory across renders. This is what makes motion event-backed rather than
   * timer-backed: without the previous `events` count there is nothing to compare. */
  var laneEls = {};
  var prevEvents = {};
  var shuttleStep = {};
  var lastGen = null;

  /* THE PROJECT PICKER'S STATE. `selectedSlug === null` means the ui directory's own root
   * `floor.json` - which is exactly what this page did before there were projects at all, and
   * remains what it does when no served index is present. */
  var SERVED_INDEX = 'index.json';
  var selectedSlug = null;
  /* THE ONLY WAY selectedSlug CHANGES. resetProjectMemory() used to be wired to the dropdown's
     onchange alone, but selectedSlug is ALSO reassigned by renderProjectPicker on paths the
     reader never touches: the served index going momentarily absent/unreadable (root fallback),
     and the "follow it" branch when the project being viewed drops out of the registry. Those
     paths switched the document while lane memory still held the PREVIOUS project's per-agent
     counts — and untyped rows fall back to a positional id ('row-' + i), so two unrelated
     projects' first untyped rows collide on "row-0" and a shuttle can advance purely because
     the old project reported a higher count at that slot. Motion with no event behind it in the
     document being rendered is the one thing this file exists to prevent, so the reset belongs
     to the ASSIGNMENT, not to one caller of it. Resets only on a real change, so the per-tick
     re-render of an unchanged selection costs nothing. */
  function setSelectedSlug(v) {
    if (v === selectedSlug) { return; }
    selectedSlug = v;
    resetProjectMemory();
  }
  var pickerSig = null;
  var pickerTouched = false;

  /* THE WRITE PATH'S THREE CONSTANTS, and all three are fixed strings in this file.
   * API_PREFIX is what makes the endpoint URLs a property of this code rather than of any
   * document it read: the same guarantee projectUrl already gives the read path. */
  var API_PREFIX = 'api/';
  var TOKEN_HEADER = 'X-Floor-Token';
  var STOP_ACTION = 'stop';

  /* THE PER-RUN TOKEN. It arrives in the URL FRAGMENT, which a browser never transmits to any
   * server, so it cannot appear in a request line, an access log, a proxy or a referrer. It is
   * read once and the fragment is removed from the address bar in the same breath, because the
   * address bar is exactly what ends up in history, in a bookmark and in a screenshot.
   * An empty token is a legitimate state, not an error: the page still READS everything. Only
   * the four buttons are refused, and they say why rather than failing silently. */
  var floorToken = '';
  (function () {
    var raw = String(window.location.hash || '');
    var m = /(?:^#|[#&])token=([A-Za-z0-9_-]+)/.exec(raw);
    if (!m) { return; }
    floorToken = m[1];
    if (window.history && window.history.replaceState) {
      try {
        window.history.replaceState(null, '', window.location.pathname + (window.location.search || ''));
      } catch (e) {
        /* A browser that refuses the rewrite must not take the page down with it: the token is
         * already held in the closure above, and the only cost is a URL that still shows it. */
      }
    }
  }());

  /* postAction — THE ONE AND ONLY WRITE CALL SITE IN THIS FILE, and the second of the two
   * `fetch(` call sites the header counts. Every part of it is deliberate:
   *   - the URL is API_PREFIX + one of four literals declared in this file, so it can never be
   *     a path a served document supplied;
   *   - the token travels in a CUSTOM header, which is what forces the CORS preflight a hostile
   *     cross-origin page cannot satisfy. A safelisted header would have made this a "simple
   *     request" - sent, and landed, before any check the browser could make;
   *   - it RESOLVES on every HTTP outcome and describes it, exactly like fetchText, so a caller
   *     never has to tell a refusal apart from a dead origin by inspecting an exception. */
  function postAction(action, payload) {
    var headers = { 'Content-Type': 'application/json' };
    headers[TOKEN_HEADER] = floorToken;
    return fetch(API_PREFIX + action, {
      method: 'POST',
      cache: 'no-store',
      headers: headers,
      body: JSON.stringify(payload || {})
    }).then(function (r) {
      return r.text().then(function (t) {
        var parsed = null;
        try { parsed = JSON.parse(t); } catch (e) { parsed = null; }
        return { status: r.status, body: parsed, text: t };
      });
    });
  }

  function fmtAge(sec) {
    if (sec === null || sec === undefined || !isFinite(sec)) { return 'unknown'; }
    if (sec < 0) { sec = 0; }
    sec = Math.floor(sec);
    if (sec < 60) { return sec + 's'; }
    var m = Math.floor(sec / 60), s = sec % 60;
    if (m < 60) { return m + 'm ' + s + 's'; }
    var h = Math.floor(m / 60); m = m % 60;
    if (h < 24) { return h + 'h ' + m + 'm'; }
    var d = Math.floor(h / 24); h = h % 24;
    return d + 'd ' + h + 'h';
  }

  function tsToEpoch(s) {
    if (typeof s !== 'string' || !s) { return null; }
    var n = Date.parse(s);
    if (!isFinite(n)) { return null; }
    return Math.floor(n / 1000);
  }

  /* An agent_type arrives doubly namespaced ("loomwright:loomwright:worker") because the
   * spawn label carries the plugin prefix once per hop. Strip EVERY leading occurrence, then
   * match the remainder against the roster's frontmatter `name`. */
  function stripPrefix(t) {
    return String(t).replace(/^(?:loomwright:)+/, '');
  }

  function surfaceOf(d, key) {
    if (!d || !d.surfaces) { return null; }
    return d.surfaces[key] || null;
  }

  /* count present -> the number; count absent -> an em dash carrying the projector's reason.
   * Never 0, never a guess. */
  function countCell(s, key) {
    if (!s) {
      return { text: '—', title: 'surface "' + key + '" is not present in floor.json' };
    }
    if (Object.prototype.hasOwnProperty.call(s, 'count') && typeof s.count === 'number') {
      return { text: String(s.count), title: s.basis || '' };
    }
    return {
      text: '—',
      title: s.reason || ('status: ' + (s.status || 'unknown') + ' - the projector recorded no count')
    };
  }

  function setCell(id, cell) {
    var node = el(id);
    if (!node) { return; }
    node.textContent = cell.text;
    node.title = cell.title || '';
    if (cell.text === '—') { node.classList.add('unknown'); } else { node.classList.remove('unknown'); }
  }

  /* The recorded phase -> pipeline stage map, and it is deliberately PARTIAL. `state.md`'s
   * `phase` is a CLOSED SET (skills/state-management/SKILL.md, §"State File Schema") and one
   * of its members is the Supervisor's between-items phase, which belongs to no stage on this
   * page. Assigning it one would be a guess, and guessing is the thing this file refuses to
   * do - so it is absent here, and it is deliberately not NAMED here either: the fallback in
   * renderStages is keyed on THIS MAP, not on any phase value, so a phase added to the closed
   * set later is handled honestly with no edit to this file. */
  var PHASE_STAGE = {
    PLAN: 'plan', ACQUIRE: 'plan', INIT: 'plan',
    EXECUTE: 'execute',
    FINALIZE: 'review', SELF_HEAL: 'review'
  };

  function banner(text) {
    var b = el('banner');
    if (!b) { return; }
    if (!text) { b.hidden = true; b.textContent = ''; return; }
    b.hidden = false;
    b.textContent = text;
  }

  /* ------------------------------------------------------------------------------------
   * THE PROJECT PICKER
   *
   * Everything below reads `index.json` - the served index the engine writes into the very
   * directory this page is served from. No new endpoint, no new timer, no write of any kind:
   * the picker changes which already-written document this page displays and nothing else.
   *
   * FOUR STATES, and they are four because they are four different claims - the same rule the
   * rules and churn views already follow:
   *   the index is ABSENT        -> no served index at this origin. Say so, and go on rendering
   *                                 the single root floor.json, which is what this page did
   *                                 before projects existed.
   *   the index is UNPARSEABLE   -> it was served and could not be read. Distinct from absent.
   *   the registry is ABSENT vs UNPARSEABLE -> two different facts about the user's own file,
   *                                 carried by the engine as `registry.state` precisely because
   *                                 both produce an empty project list. Never collapsed.
   *   a project row               -> ready / never regenerated / unavailable / unreadable age,
   *                                 each with the engine's own reason.
   * ------------------------------------------------------------------------------------ */

  /* projectUrl is built HERE, from a fixed prefix and an encoded slug, and never from a URL
   * the index supplies. encodeURIComponent leaves no `/` and no `:` intact, so a served index
   * carrying a hostile slug still resolves to a path inside this origin's own projects
   * directory. The CSP would refuse an off-origin fetch anyway; this makes the guarantee a
   * property of the code rather than only of a header. */
  function projectUrl(slug) {
    if (!slug) { return 'floor.json'; }
    return 'projects/' + encodeURIComponent(slug) + '/floor.json';
  }

  /* projectStateLabel -> the honest one-line state of one project row. Every branch names the
   * engine's own `reason` when there is one and says that there is none when there is not; an
   * unrecognised state is NAMED rather than rendered as any of the states this page does know,
   * because an artefact from a newer engine must not be silently mapped onto the wrong claim. */
  function projectStateLabel(p) {
    if (!p || Object.prototype.toString.call(p) !== '[object Object]') {
      return 'this row is not a project record';
    }
    if (!Object.prototype.hasOwnProperty.call(p, 'state')) {
      return 'the served index records no state for this project';
    }
    var st = String(p.state);
    var why = (typeof p.reason === 'string' && p.reason)
      ? (' — ' + p.reason)
      : ' — the served index records no reason';
    if (st === 'unavailable') { return 'unavailable' + why; }
    if (st === 'never-regenerated') { return 'never regenerated' + why; }
    if (st === 'unreadable') { return 'age unknown' + why; }
    if (st === 'ready') {
      if (typeof p.last_regenerated_epoch !== 'number') {
        return 'regenerated, but the served index records no time for it';
      }
      return 'last regenerated ' + fmtAge(Math.floor(Date.now() / 1000) - p.last_regenerated_epoch) + ' ago';
    }
    return 'state "' + st + '" is not one this page knows how to render';
  }

  /* registryStateLabel -> ABSENT and UNPARSEABLE said as the two different things they are.
   * A registry that was never created is the normal state of a fresh install; one that cannot
   * be parsed is a file the user has and this module refuses to touch. Reporting either as the
   * other would send a reader to fix the wrong thing. */
  function registryStateLabel(reg) {
    if (!reg || Object.prototype.toString.call(reg) !== '[object Object]') {
      return 'the served index carries no registry state';
    }
    if (!Object.prototype.hasOwnProperty.call(reg, 'state')) {
      return 'the served index carries no registry state';
    }
    var st = String(reg.state);
    var why = (typeof reg.reason === 'string' && reg.reason) ? (' — ' + reg.reason) : '';
    var where = (typeof reg.path === 'string' && reg.path) ? (' (' + reg.path + ')') : '';
    if (st === 'ok') { return 'registry read' + where; }
    if (st === 'absent') { return 'registry absent: no projects are registered yet' + where + why; }
    if (st === 'unparseable') { return 'registry unparseable: the file is there but could not be read' + where + why; }
    if (st === 'unreadable') { return 'registry unreadable' + where + why; }
    if (st === 'unnameable') { return 'registry unnameable' + where + why; }
    return 'registry state "' + st + '" is not one this page knows how to render';
  }

  function projectRows(idx) {
    var rows = idx && idx.projects;
    if (Object.prototype.toString.call(rows) !== '[object Array]') { return []; }
    return rows;
  }

  /* renderProjectPicker — the whole projects section: the select, the per-project list and the
   * cadence note. Called on every tick from the ONE existing poll; it starts no timer.
   *
   * The <select> is rebuilt only when its OPTION SET changes (a signature over the slugs), not
   * on every tick: rebuilding it every two seconds would silently snap the reader's choice back
   * to the default while they were looking at another project. The per-project list beside it
   * IS rebuilt every tick, because it is text and its ages must move. */
  function renderProjectPicker(idx) {
    var sel = el('project-picker');
    var host = el('project-rows');
    var note = el('project-note');
    var regEl = el('registry-state');
    if (!sel || !host) { return; }

    if (!idx || idx.absent === true) {
      sel.hidden = true;
      host.innerHTML = '';
      if (regEl) { regEl.textContent = ''; }
      if (note) {
        note.textContent = (idx && idx.parseError)
          ? ('the served index was served but could not be read (' + idx.parseError + ') — showing the single floor.json this directory serves')
          : ((idx && idx.fetchError)
            ? ('the served index could not be read (' + idx.fetchError + ') — showing the single floor.json this directory serves')
            : 'no served index at this origin — showing the single floor.json this directory serves. `setup-ui.sh serve` writes one.');
      }
      setSelectedSlug(null);
      pickerSig = null;
      return;
    }

    var rows = projectRows(idx);
    var srv = (idx.serve && Object.prototype.toString.call(idx.serve) === '[object Object]') ? idx.serve : {};
    if (regEl) { regEl.textContent = registryStateLabel(idx.registry); }

    /* The root option exists only when the directory this serve was launched in is NOT one of
     * the registered projects. When it IS registered, its slot document and the root
     * floor.json are the same bytes, and offering both would be two names for one thing. */
    var rootOption = (srv.selected_registered !== true);
    var i, sig = (rootOption ? '*root*' : '');
    for (i = 0; i < rows.length; i++) { sig += '|' + String(rows[i] && rows[i].slug); }

    if (sig !== pickerSig) {
      pickerSig = sig;
      sel.innerHTML = '';
      var opt;
      if (rootOption) {
        opt = document.createElement('option');
        opt.value = '';
        opt.textContent = (typeof srv.selected_path === 'string' && srv.selected_path)
          ? ('this serve’s own directory — ' + srv.selected_path + ' (not registered)')
          : 'this serve’s own directory (not registered)';
        sel.appendChild(opt);
      }
      for (i = 0; i < rows.length; i++) {
        var r = rows[i] || {};
        opt = document.createElement('option');
        opt.value = String(r.slug === undefined ? '' : r.slug);
        opt.textContent = String(r.slug === undefined ? '(no slug recorded)' : r.slug) +
          (r.selected === true ? ' — selected by this serve' : '');
        sel.appendChild(opt);
      }
      /* Only the FIRST build chooses for the reader, and it chooses what the engine is
       * actually regenerating on the fast cadence. After that the reader's choice wins, even
       * across a registry change, because clobbering it would be motion they did not ask for. */
      if (!pickerTouched) {
        /* Computed into a local and assigned ONCE: assigning through the setter inside the loop
           would reset lane memory two or three times for a single decision. */
        var chosen = null;
        for (i = 0; i < rows.length; i++) {
          if (rows[i] && rows[i].selected === true) { chosen = String(rows[i].slug); break; }
        }
        if (chosen === null && !rootOption && rows.length) { chosen = String(rows[0].slug); }
        setSelectedSlug(chosen);
      }
      sel.value = (selectedSlug === null) ? '' : selectedSlug;
      /* If the project the reader was on has gone from the registry, the select would silently
       * fall back to its first option while this page kept fetching the old slug. Follow it. */
      if (sel.value !== ((selectedSlug === null) ? '' : selectedSlug)) {
        setSelectedSlug(sel.value === '' ? null : sel.value);
      }
    }
    sel.hidden = false;

    host.innerHTML = '';
    if (!rows.length) {
      var liNone = document.createElement('li');
      liNone.className = 'empty';
      liNone.textContent = 'no projects registered — `setup-ui.sh add`, run inside a project, puts one here. A project appears on this page only because a human added it.';
      host.appendChild(liNone);
    }
    for (i = 0; i < rows.length; i++) {
      var p = rows[i] || {};
      var li = document.createElement('li');
      li.className = 'project';
      if (p.state === 'unavailable') { li.classList.add('unavailable'); }
      if (String(p.slug) === String(selectedSlug)) { li.classList.add('showing'); }

      var nameEl = document.createElement('span');
      nameEl.className = 'project-slug';
      nameEl.textContent = (p.slug === undefined) ? '(no slug recorded)' : String(p.slug);
      li.appendChild(nameEl);

      var pathEl = document.createElement('span');
      pathEl.className = 'project-path';
      pathEl.textContent = ' ' + ((typeof p.path === 'string' && p.path) ? p.path : '(no path recorded)');
      li.appendChild(pathEl);

      var stEl = document.createElement('span');
      stEl.className = 'project-state';
      stEl.textContent = ' · ' + projectStateLabel(p);
      li.appendChild(stEl);
      host.appendChild(li);
    }

    if (note) {
      /* The cadence is READ from the served index, never assumed: this page cannot see
       * `--interval` and the slow factor is the engine's constant, not the page's. Stating
       * both is what makes a project that is legitimately old readable as such. */
      var bits = [];
      if (typeof srv.interval_seconds === 'number') {
        bits.push('the project this serve was launched in regenerates every ' + srv.interval_seconds + 's');
        if (typeof srv.slow_cadence_ticks === 'number') {
          bits.push('every other registered project one at a time every ' +
            (srv.interval_seconds * srv.slow_cadence_ticks) + 's');
        }
      }
      if (srv.regen === false) { bits.push('regeneration is OFF for this serve (--no-regen), so every age below is frozen'); }
      note.textContent = bits.length
        ? (bits.join(' · ') + '. Selecting a project switches what this page reads; it never asks the server to regenerate anything.')
        : 'the served index records no cadence for this serve';
    }
  }

  /* Lane memory belongs to ONE project's document. Carrying it across a switch would let a
   * shuttle advance because two different projects reported different counts - motion with no
   * event behind it, which is the one thing this file exists to prevent. */
  function resetProjectMemory() {
    var k;
    for (k in laneEls) {
      if (Object.prototype.hasOwnProperty.call(laneEls, k)) {
        if (laneEls[k].parentNode) { laneEls[k].parentNode.removeChild(laneEls[k]); }
      }
    }
    laneEls = {};
    prevEvents = {};
    shuttleStep = {};
    lastGen = null;
    apply.lanes = 0;
  }

  function rosterIndex(d) {
    var idx = {}, s = surfaceOf(d, 'agents'), i;
    var rows = (s && s.detail && s.detail.roster) || [];
    for (i = 0; i < rows.length; i++) {
      if (rows[i] && rows[i].name) { idx[rows[i].name] = rows[i]; }
    }
    return idx;
  }

  function renderStages(d) {
    setCell('st-queue', countCell(surfaceOf(d, 'jobs_pending'), 'jobs_pending'));
    setCell('st-shipped', countCell(surfaceOf(d, 'jobs_done'), 'jobs_done'));

    var state = surfaceOf(d, 'state');
    var phase = (state && state.detail && state.detail.phase) || null;
    /* A RECORDED PHASE THE MAP DOES NOT KNOW IS NOT THE SAME AS NO PHASE AT ALL, and this is
     * the one place the two shapes would otherwise become indistinguishable: both leave all
     * three middle cells at an em dash - which is TRUE, no stage is active - and a reader
     * would then be looking at a measured state rendered exactly like an absent one. So the
     * stage cells stay honest and the phase-note below states the recorded value instead.
     * hasOwnProperty rather than a truthy lookup: PHASE_STAGE['constructor'] is a function,
     * which would light up no stage while reporting itself as mapped. */
    var mapped = (phase !== null && Object.prototype.hasOwnProperty.call(PHASE_STAGE, phase))
      ? PHASE_STAGE[phase] : null;
    var unmapped = (phase !== null && mapped === null);
    var active = mapped;
    var mids = ['plan', 'execute', 'review'], i, node;
    for (i = 0; i < mids.length; i++) {
      node = document.querySelector('.stage[data-stage="' + mids[i] + '"]');
      if (!node) { continue; }
      if (active === mids[i]) { node.classList.add('active'); } else { node.classList.remove('active'); }
    }
    for (i = 0; i < mids.length; i++) {
      var vid = 'st-' + mids[i];
      if (active === mids[i]) {
        setCell(vid, { text: phase, title: 'state.detail.phase, as recorded in .supervisor/state.md' });
      } else {
        setCell(vid, {
          text: '—',
          title: phase
            ? ('the recorded phase is ' + phase + (unmapped ? ' — no pipeline stage corresponds to it' : ''))
            : 'no phase is recorded'
        });
      }
    }

    var note = el('phase-note');
    if (note) {
      if (!state) {
        note.textContent = 'no state surface in floor.json';
      } else if (state.status !== 'counted') {
        note.textContent = 'state surface ' + state.status + ': ' + (state.reason || 'no reason recorded');
      } else {
        var age = (typeof state.mtime_epoch === 'number' && typeof d.generated_at_epoch === 'number')
          ? ('state.md last written ' + fmtAge(d.generated_at_epoch - state.mtime_epoch) + ' before this projection')
          : 'state.md write time unknown';
        var br = (state.detail && state.detail.branch) ? (' · branch ' + state.detail.branch) : '';
        var rs = (state.detail && state.detail.run_status) ? (' · recorded run_status ' + state.detail.run_status) : '';
        /* The two shapes the stage cells cannot tell apart, said in words. Both are TEXT, set
         * through textContent like everything else on this page. */
        var ph = unmapped
          ? (' · recorded phase ' + phase + ' — no pipeline stage corresponds to it')
          : (phase ? '' : ' · no phase is recorded');
        note.textContent = age + br + rs + ph;
      }
    }
  }

  /* The projector states its omissions twice: as a `reason` on the surface (which the schema
   * documents for a surface whose status is not `counted`) and as a line in `notes[]` that
   * starts with the surface key. This walks that ladder in order and NAMES its fallback, so a
   * banner can never present the page's own guess as the projector's finding. */
  function noteFor(d, key) {
    var notes = (d && d.notes) || [], i, t;
    for (i = 0; i < notes.length; i++) {
      t = String(notes[i]);
      if (t.indexOf(key + ' ') === 0) { return t; }
    }
    return null;
  }

  function reasonFor(d, s, key) {
    if (s && s.reason) { return String(s.reason); }
    var n = noteFor(d, key);
    if (n) { return n; }
    return 'the projector recorded no reason for this surface';
  }

  /* RULES BROWSER + CHURN VIEW. Both views read ONLY the `rules` / `postmortem` surfaces the
   * projector already carries — no new fetch, no new endpoint, no new timer. Both honour the
   * same four-state contract as the rest of the page: absent (surface key missing), unverified
   * (present but the projector names a reason it could not fully read it — the survivable
   * partial detail is still shown), a counted surface with nothing in it (empty), and a
   * counted surface with recorded rows (the browsable case). NOTHING here ranks, scores or
   * sorts by desirability: every list below is sorted by KEY (category name, scope text, class
   * name), never by a count, and a correlation is rendered as a labelled observation with its
   * evidence, never as a rate. */

  function clearHost(id) {
    var h = el(id);
    if (h) { h.innerHTML = ''; }
    return h;
  }

  /* surfaceState mirrors countCell's absent/unverified/counted trichotomy but returns the
   * surface itself rather than a rendered cell, because both views need the surface's own
   * `detail` to render anything beyond the state banner. */
  function surfaceState(d, key) {
    var s = surfaceOf(d, key);
    if (!s) { return { state: 'absent', s: null }; }
    if (s.status === 'absent') { return { state: 'absent', s: s }; }
    if (s.status === 'unverified') { return { state: 'unverified', s: s }; }
    return { state: 'counted', s: s };
  }

  function sortedKeys(obj) {
    var keys = [], k;
    for (k in obj) { if (Object.prototype.hasOwnProperty.call(obj, k)) { keys.push(k); } }
    keys.sort();
    return keys;
  }

  /* applies_to is a genuine TRI-STATE, decided by key PRESENCE, never by truthiness: the key
   * absent, present-and-null, or a (possibly empty) array. A truthy test would collapse a
   * declared-null rule into "no scope recorded", which is a different, false claim. */
  function ruleScopeLabel(r) {
    if (!Object.prototype.hasOwnProperty.call(r, 'applies_to')) { return 'no scope recorded'; }
    var v = r.applies_to;
    if (v === null) { return 'declared repo-wide (applies_to recorded as null)'; }
    if (Object.prototype.toString.call(v) === '[object Array]') {
      return v.length ? ('scoped to ' + v.join(', ')) : 'declared with an empty glob list';
    }
    /* FOURTH state: the key is present but the value is neither null nor an array - most often
     * a bare string glob written without the array brackets. Returning the absent-key text here
     * would collapse "declared, but malformed" into "never declared", which is the very defect
     * class the null branch above exists to prevent, one branch later. It is not hypothetical:
     * read-rules.sh carries a dedicated WARN channel for a malformed applies_to, and
     * build-floor.sh forwards the value verbatim whenever the key is present without validating
     * its shape - so this reaches the page intact. Name the type so the author can see what the
     * store actually holds. */
    return 'applies_to is present but malformed (' +
      (Object.prototype.toString.call(v) === '[object String]' ? 'a bare string, not an array'
        : (('aeiou'.indexOf((typeof v).charAt(0)) >= 0 ? 'an ' : 'a ') + typeof v)) +
      ') — scope not interpretable';
  }

  /* check gets the identical tri-state treatment for the identical reason. The string is
   * rendered as DATA via textContent below — it is never evaluated or executed. */
  /* The THIRD of the three optional rule fields, and it was left raw when applies_to and check
   * were guarded one commit earlier (2337397) - the same class, one field over. The projector
   * forwards `supersedes` on key presence with no type filter, while its OWN edge walk selects
   * `type == "string"`; so a non-string is silently excluded from chains/dangling/cycles and yet
   * still printed on the card, leaving the walk and the card disagreeing about what the value is.
   * add-rule.sh never writes a non-string here, so this reaches the page only via a hand-edited
   * store - but applies_to is equally validated by add-rule.sh and was still guarded. */
  function ruleSupersedesLabel(r) {
    if (!Object.prototype.hasOwnProperty.call(r, 'supersedes')) { return null; }
    var v = r.supersedes;
    if (v === null) { return 'supersedes: declared, but recorded as null — names no rule'; }
    if (Object.prototype.toString.call(v) !== '[object String]') {
      return 'supersedes is present but malformed (' +
        ('aeiou'.indexOf((typeof v).charAt(0)) >= 0 ? 'an ' : 'a ') + typeof v +
        '), so the supersession walk excluded it';
    }
    if (!v) { return 'supersedes: declared, but empty — names no rule'; }
    return 'supersedes: ' + v;
  }

  /* provenance is an OBJECT ({source, added}) and was concatenated straight into the meta line,
   * rendering "provenance: [object Object]" on EVERY rule card against the real store - not an
   * edge case reachable only from a hand-edited store, but the default render. Found while
   * verifying the supersedes fix in a browser; it is the fourth field of four to need this, and
   * the only one where the junk was already on screen. Show the fields, and say so plainly when
   * the value is not the object shape read-rules.sh documents. */
  function ruleProvenanceLabel(r) {
    var v = r.provenance;
    if (v === undefined || v === null) { return null; }
    if (Object.prototype.toString.call(v) === '[object String]') { return 'provenance: ' + v; }
    if (Object.prototype.toString.call(v) !== '[object Object]') {
      return 'provenance is present but malformed (' +
        ('aeiou'.indexOf((typeof v).charAt(0)) >= 0 ? 'an ' : 'a ') + typeof v + ')';
    }
    /* PRESENCE, not truthiness - the same correction every sibling field in this file already
     * got, and the one place it was missed. `&& v.source` dropped a present-but-EMPTY source,
     * and when both fields were empty the function then claimed the object "carries no source or
     * added field" while both keys were demonstrably there. A false statement about the store,
     * which is worse than the bare render it was written to avoid. build-floor.sh forwards
     * provenance verbatim on has() without validating the inner shape, so an empty string is a
     * value this page can actually receive. */
    var parts = [];
    var hasSrc = Object.prototype.hasOwnProperty.call(v, 'source');
    var hasAdd = Object.prototype.hasOwnProperty.call(v, 'added');
    if (hasSrc) {
      parts.push(typeof v.source === 'string'
        ? (v.source === '' ? 'source declared, but empty' : v.source)
        : 'source is not a string');
    }
    if (hasAdd) {
      parts.push(typeof v.added === 'string'
        ? (v.added === '' ? 'added declared, but empty' : 'added ' + v.added)
        : 'added is not a string');
    }
    /* Only when NEITHER key is present is "carries no source or added field" a true statement. */
    return parts.length ? ('provenance: ' + parts.join(' · '))
                        : 'provenance is recorded but carries no source or added field';
  }

  function ruleCheckLabel(r) {
    if (!Object.prototype.hasOwnProperty.call(r, 'check')) { return 'no check declared'; }
    if (r.check === null) { return 'declared, no runnable check (null)'; }
    /* read-rules.sh types this `string | null`. Anything else is malformed, and concatenating it
     * would render "[object Object]" - junk that reads like content. Same reasoning as
     * ruleScopeLabel's fourth state: say what it is instead. */
    if (Object.prototype.toString.call(r.check) !== '[object String]') {
      return 'check is present but malformed (' +
        ('aeiou'.indexOf((typeof r.check).charAt(0)) >= 0 ? 'an ' : 'a ') + typeof r.check +
        '), not a runnable string';
    }
    /* An empty check is legal (read-rules.sh types it `string | null`) and used to render as a
     * bare "check: " with nothing after the colon. Name it, the way `enforcement` does. */
    return r.check === '' ? 'check: declared, but empty' : 'check: ' + r.check;
  }

  function renderRules(d) {
    var basisEl = el('rules-basis');
    var srcEl = el('rules-src');
    var body = clearHost('rules-body');
    if (!body) { return; }
    var st = surfaceState(d, 'rules');

    if (st.state === 'absent') {
      if (basisEl) { basisEl.textContent = ''; }
      if (srcEl) { srcEl.textContent = ''; }
      var pAbsent = document.createElement('p');
      pAbsent.className = 'empty';
      pAbsent.textContent = st.s
        ? ('rules surface ' + st.s.status + ': ' + reasonFor(d, st.s, 'rules'))
        : 'rules surface is not present in floor.json';
      body.appendChild(pAbsent);
      return;
    }

    var s = st.s;
    if (basisEl) { basisEl.textContent = s.basis || ''; }
    if (st.state === 'unverified') {
      var pUnv = document.createElement('p');
      pUnv.className = 'view-banner';
      pUnv.textContent = 'could not examine every rule file: ' + reasonFor(d, s, 'rules');
      body.appendChild(pUnv);
      /* fall through: the valid files' rules, if any, are still rendered below — "could not
       * examine X" must never read as "examined and clean" for the files that DID parse. */
    }

    var detail = s.detail || {};
    var rows = detail.rules || [];
    if (srcEl) {
      /* NO FALLBACK TO rows.length. When the surface carries no `detail` at all - an artefact
       * from a projector older than this page, which `schema_version: 1` deliberately keeps
       * legal - rows is [] and a rows.length fallback would print "(0 rule(s))" for a store the
       * projector actually counted: the banned shape named in this file's own header rule
       * (absent evidence is rendered as unknown, never as zero). Cite the surface's own `count`,
       * which IS recorded, and say plainly that the detail is missing. */
      if (typeof detail.rules_parsed === 'number') {
        srcEl.textContent = '(' + detail.rules_parsed + ' rule(s)' +
          (detail.read_completeness ? (' · read ' + detail.read_completeness) : '') + ')';
      } else if (st.s && st.s.count === 0) {
        srcEl.textContent = '(0 rule(s))';
      } else if (st.s && typeof st.s.count === 'number') {
        /* surfaceState returns { state, s } - the surface object is under `.s`. Reading
         * `st.count` here was a branch that could never fire, which is the same
         * guard-that-cannot-fire class this render is guarding against. */
        srcEl.textContent = '(' + st.s.count + ' file(s) counted · no rule detail in this projection)';
      } else {
        srcEl.textContent = '(no rule detail in this projection)';
      }
    }

    var unparse = detail.files_unparseable || [];
    if (unparse.length) {
      var ulU = document.createElement('ul');
      ulU.className = 'notes';
      for (var u = 0; u < unparse.length; u++) {
        var fu = unparse[u] || {};
        var liU = document.createElement('li');
        liU.textContent = 'could not examine ' + (fu.file || 'a file') + ': ' + (fu.reason || 'no reason recorded');
        ulU.appendChild(liU);
      }
      body.appendChild(ulU);
    }

    /* "Parsed as JSON, but not the ARRAY this store uses" is a THIRD outcome, distinct from both
     * unparseable and clean — the projector's own comment calls it the difference between
     * "held no rules" and "was never understood". It was emitted and rendered nowhere, so on the
     * page a misunderstood file looked exactly like a file that simply held nothing. */
    var notArr = detail.files_not_an_array || [];
    if (notArr.length) {
      var ulNA = document.createElement('ul');
      ulNA.className = 'notes';
      for (var na = 0; na < notArr.length; na++) {
        var liNA = document.createElement('li');
        liNA.textContent = 'parsed but not understood: ' + (notArr[na] || 'a file') +
          ' holds valid JSON that is not the array of rule objects this store uses';
        ulNA.appendChild(liNA);
      }
      body.appendChild(ulNA);
    }

    if (!rows.length) {
      var pEmpty = document.createElement('p');
      pEmpty.className = 'empty';
      /* "no rules recorded" is a CLAIM about an examined store, so it is made only when the
       * evidence supports it. Measured: a genuinely EMPTY store and an artefact from a projector
       * older than this page produce the SAME shape - status counted, no `detail` - so `detail`
       * alone cannot separate them. `count` can, and does: zero files means there is nothing to
       * browse whether or not detail was supplied, while a positive count with no detail means
       * this page cannot enumerate a store the projector did count. Saying "no rules recorded"
       * for that second case is the fabricated zero; saying it for the first is simply true. */
      if (typeof detail.rules_parsed !== 'number'
          && !(st.s && st.s.count === 0)) {
        pEmpty.textContent = 'this projection carries no rule detail — regenerate floor.json with a current projector to browse the store';
        body.appendChild(pEmpty);
        return;
      }
      pEmpty.textContent = 'no rules recorded';
      body.appendChild(pEmpty);
      return;
    }

    var byCat = {}, catOrder = [], i;
    for (i = 0; i < rows.length; i++) {
      var r = rows[i] || {};
      var cat = r.category || 'uncategorised';
      if (!Object.prototype.hasOwnProperty.call(byCat, cat)) { byCat[cat] = []; catOrder.push(cat); }
      byCat[cat].push(r);
    }
    catOrder.sort();

    var corrIndex = {}, corr = detail.correlations || [], c;
    for (c = 0; c < corr.length; c++) {
      if (corr[c] && corr[c].rule_id) { corrIndex[corr[c].rule_id] = corr[c]; }
    }

    for (var ci = 0; ci < catOrder.length; ci++) {
      var catName = catOrder[ci];
      var h3 = document.createElement('h3');
      h3.className = 'rules-category';
      h3.textContent = catName;
      body.appendChild(h3);

      var byScope = {}, scopeOrder = [], j;
      var catRows = byCat[catName];
      for (j = 0; j < catRows.length; j++) {
        var scope = ruleScopeLabel(catRows[j]);
        if (!Object.prototype.hasOwnProperty.call(byScope, scope)) { byScope[scope] = []; scopeOrder.push(scope); }
        byScope[scope].push(catRows[j]);
      }
      scopeOrder.sort();

      for (var si = 0; si < scopeOrder.length; si++) {
        var h4 = document.createElement('h4');
        h4.className = 'rules-scope';
        h4.textContent = scopeOrder[si];
        body.appendChild(h4);

        var ulR = document.createElement('ul');
        ulR.className = 'rules-list';
        var scopeRows = byScope[scopeOrder[si]];
        for (var k = 0; k < scopeRows.length; k++) {
          var rule = scopeRows[k];
          var li = document.createElement('li');
          li.className = 'rule-card';

          var idLine = document.createElement('div');
          idLine.className = 'rule-id';
          idLine.textContent = rule.id || '(no id recorded)';
          li.appendChild(idLine);

          var stmt = document.createElement('p');
          stmt.textContent = rule.statement || '(no statement recorded)';
          li.appendChild(stmt);

          var meta = document.createElement('p');
          meta.className = 'rule-meta';
          var bits = [];
          /* Key presence, not truthiness - the standard every other field in this file is held
           * to, and this was the one exception. build-floor.sh forwards ANY string including "",
           * which a truthy test silently drops: a rule that recorded an empty enforcement would
           * render identically to one that recorded none. Same nullable-required-field class the
           * `check` field already cost this repo once. */
          if (Object.prototype.hasOwnProperty.call(rule, 'enforcement')) {
            bits.push(rule.enforcement === ''
              ? 'enforcement: declared, but empty'
              : 'enforcement: ' + rule.enforcement);
          }
          var provLabel = ruleProvenanceLabel(rule);
          if (provLabel !== null) { bits.push(provLabel); }
          bits.push(ruleCheckLabel(rule));
          meta.textContent = bits.join(' · ');
          li.appendChild(meta);

          var supLabel = ruleSupersedesLabel(rule);
          if (supLabel !== null) {
            var supP = document.createElement('p');
            supP.className = 'rule-meta';
            supP.textContent = supLabel;
            li.appendChild(supP);
          }

          var rc = rule.id ? corrIndex[rule.id] : null;
          if (rc) {
            var corrDiv = document.createElement('div');
            corrDiv.className = 'rule-correlation';
            var corrHead = document.createElement('p');
            corrHead.textContent = (rc.label || 'observation') + ' — not a measurement: ' + (rc.basis || '');
            corrDiv.appendChild(corrHead);
            var ulEv = document.createElement('ul');
            var matched = rc.matched || [];
            for (var m = 0; m < matched.length; m++) {
              var mm = matched[m] || {};
              var liEv = document.createElement('li');
              var evTxt = 'line ' + mm.line + ' · ' + mm.path + ' matched ' + mm.pattern;
              /* Evidence is carried ONCE PER CORRELATION in `evidence_by_line`, keyed by line -
               * `matched[].line` is the key into it. This branch used to read `mm.evidence`, which
               * the projector stopped emitting when the evidence was hoisted to kill a ~4x
               * duplication; the read was not updated, so the branch was DEAD for every artefact
               * the current projector can produce and every correlation rendered as a label and a
               * basis with nothing under it - while three doc surfaces claimed the evidence was
               * shown. The `mm.evidence` fallback is kept for an artefact produced BEFORE the
               * hoist, which schema_version 1 still makes legal. */
              var evList = (mm.evidence && mm.evidence.length) ? mm.evidence
                         : ((rc.evidence_by_line || {})[String(mm.line)] || []);
              if (evList.length) { evTxt += ' — evidence: ' + evList.join('; '); }
              else { evTxt += ' — no evidence recorded for this line'; }
              liEv.textContent = evTxt;
              ulEv.appendChild(liEv);
            }
            corrDiv.appendChild(ulEv);
            li.appendChild(corrDiv);
          }

          ulR.appendChild(li);
        }
        body.appendChild(ulR);
      }
    }

    var sup = detail.supersedes;
    if (sup) {
      var h3s = document.createElement('h3');
      h3s.className = 'rules-category';
      h3s.textContent = 'Supersession history';
      body.appendChild(h3s);

      var ulS = document.createElement('ul');
      ulS.className = 'notes';
      var chains = sup.chains || [], dangling = sup.dangling || [], cycles = sup.cycles || [];
      for (var ch = 0; ch < chains.length; ch++) {
        var liCh = document.createElement('li');
        liCh.textContent = 'chain: ' + chains[ch].join(' → ');
        ulS.appendChild(liCh);
      }
      for (var dg = 0; dg < dangling.length; dg++) {
        var dd = dangling[dg] || {};
        var liDg = document.createElement('li');
        liDg.textContent = 'dangling: ' + dd.from + ' supersedes ' + dd.to + ', which does not exist in the parsed set';
        ulS.appendChild(liDg);
      }
      for (var cy = 0; cy < cycles.length; cy++) {
        var liCy = document.createElement('li');
        liCy.textContent = 'cycle: ' + cycles[cy].join(' → ') + ' → ' + cycles[cy][0];
        ulS.appendChild(liCy);
      }
      /* Two more shapes the walk records and the page used to drop on the floor. Both are
       * curation faults a browser of curation history exists to surface. */
      var selfRef = sup.self_referential || [], dupIds = sup.duplicate_ids || [];
      for (var sr = 0; sr < selfRef.length; sr++) {
        var liSR = document.createElement('li');
        liSR.textContent = 'self-referential: ' + selfRef[sr] + ' names itself, so it supersedes nothing';
        ulS.appendChild(liSR);
      }
      for (var di = 0; di < dupIds.length; di++) {
        var liDI = document.createElement('li');
        /* "first seen wins" was FALSE in both readings available, and this is the ONLY sentence
         * on the page that states a resolution rule - in the view whose whole premise is
         * reporting curation history faithfully. The edge map is `add` over single-key objects,
         * which is LAST-write-wins (documented and verified at the edge_map site in
         * build-floor.sh: two `dup` rules superseding `target` and `other` yield the chain
         * ["dup","other"], the first edge gone), and `rules[]` dedups nothing at all - both rows
         * are emitted and rendered above this line. Say what actually happens. */
        liDI.textContent = 'duplicate id: ' + dupIds[di] +
          ' appears more than once in the merged store — both rows are listed above; where duplicates carry different supersedes values the walk follows the last';
        ulS.appendChild(liDI);
      }
      if (!chains.length && !dangling.length && !cycles.length && !selfRef.length && !dupIds.length) {
        var liNone = document.createElement('li');
        liNone.className = 'empty';
        liNone.textContent = 'no chains, dangling pointers or cycles recorded';
        ulS.appendChild(liNone);
      }
      body.appendChild(ulS);
    }
  }

  function renderDistribution(host, obj, label) {
    var ul = document.createElement('ul');
    ul.className = 'churn-dist';
    var keys = sortedKeys(obj || {}), i;
    if (!keys.length) {
      var li0 = document.createElement('li');
      li0.className = 'empty';
      li0.textContent = 'no ' + label + ' recorded';
      ul.appendChild(li0);
    } else {
      for (i = 0; i < keys.length; i++) {
        var li = document.createElement('li');
        li.textContent = keys[i] + ': ' + obj[keys[i]];
        ul.appendChild(li);
      }
    }
    host.appendChild(ul);
  }

  function renderChurn(d) {
    var basisEl = el('churn-basis');
    var srcEl = el('churn-src');
    var body = clearHost('churn-body');
    if (!body) { return; }
    var st = surfaceState(d, 'postmortem');

    if (st.state === 'absent') {
      if (basisEl) { basisEl.textContent = ''; }
      if (srcEl) { srcEl.textContent = ''; }
      var pAbsent = document.createElement('p');
      pAbsent.className = 'empty';
      pAbsent.textContent = st.s
        ? ('postmortem surface ' + st.s.status + ': ' + reasonFor(d, st.s, 'postmortem'))
        : 'postmortem surface is not present in floor.json';
      body.appendChild(pAbsent);
      return;
    }

    var s = st.s;
    var detail = s.detail || {};
    /* THE BASIS IS READ FROM THE PROJECTION, NEVER RESTATED. flow_stage_basis exists precisely
     * because the ledger carries two disagreeing flow-stage representations (see build-floor.sh);
     * a literal copy of the chosen predicate here would be a second place for that choice to
     * drift out of sync with the one the projector actually applied. */
    if (basisEl) {
      var basisBits = [];
      if (detail.class_basis) { basisBits.push('class basis: ' + detail.class_basis); }
      if (detail.flow_stage_basis) { basisBits.push('flow-stage basis: ' + detail.flow_stage_basis); }
      basisEl.textContent = basisBits.length ? basisBits.join(' · ') : (s.basis || '');
    }
    if (st.state === 'unverified') {
      var pUnv = document.createElement('p');
      pUnv.className = 'view-banner';
      pUnv.textContent = 'could not examine every ledger line: ' + reasonFor(d, s, 'postmortem');
      body.appendChild(pUnv);
    }
    if (srcEl) {
      var bits = [];
      if (typeof detail.categories_total === 'number') { bits.push(detail.categories_total + ' categorised finding(s)'); }
      if (typeof detail.lines_without_categories === 'number') { bits.push(detail.lines_without_categories + ' line(s) without categories'); }
      if (typeof detail.flow_stage_counter_disagreements === 'number') {
        bits.push(detail.flow_stage_counter_disagreements + ' disagreement(s) with the unpublished flow-stage counter');
      }
      srcEl.textContent = bits.length ? ('(' + bits.join(' · ') + ')') : '';
    }

    var classKeys = sortedKeys(detail.class_distribution || {});
    var flowKeys = sortedKeys(detail.flow_stage_distribution || {});
    if (!classKeys.length && !flowKeys.length) {
      var pEmpty = document.createElement('p');
      pEmpty.className = 'empty';
      /* Same distinction as renderRules above: an EMPTY distribution is "no churn recorded";
       * a projection carrying no churn detail at all was never examined and says so. */
      pEmpty.textContent = (typeof detail.categories_total === 'number' || (st.s && st.s.count === 0))
        ? 'no churn recorded'
        : 'this projection carries no churn detail — regenerate floor.json with a current projector';
      body.appendChild(pEmpty);
    } else {
      var h3c = document.createElement('h3');
      h3c.className = 'rules-category';
      h3c.textContent = 'By root-cause class';
      body.appendChild(h3c);
      renderDistribution(body, detail.class_distribution, 'classes');

      var h3f = document.createElement('h3');
      h3f.className = 'rules-category';
      h3f.textContent = 'By flow stage';
      body.appendChild(h3f);
      renderDistribution(body, detail.flow_stage_distribution, 'flow stages');
    }

    var malformed = detail.malformed_lines || [];
    if (malformed.length) {
      var pMal = document.createElement('p');
      pMal.className = 'view-banner';
      pMal.textContent = 'malformed line(s), never folded into any class: ' + malformed.join(', ');
      body.appendChild(pMal);
    }
  }

  /* IDLE IS A MEASURED STATE, NEVER A DEFAULT. An empty lane list has three very different
   * causes and only one of them is "nothing is running":
   *   - sessions counted + `current` present + zero agents  -> a session was identified and
   *     no agent event was recorded in it. That is a MEASURED zero, and the projector records
   *     it by OMITTING `agents` from `current` rather than emitting `[]` (the omit-not-zero
   *     rule), so a missing key and an empty array both read as zero here.
   *   - sessions counted + `current` OMITTED -> no line carried a `ts`, so the newest session
   *     could not be identified at all. The projector refused to state this; the page must
   *     not answer for it, least of all while the state surface beside it records a phase.
   *   - sessions absent / unverified -> the input was missing or could not be read.
   * This mirrors renderStages' treatment of the sibling `state` surface exactly. */
  function sessionsVerdict(d) {
    var s = surfaceOf(d, 'sessions');
    if (!s) { return { idle: false, reason: 'floor.json carries no sessions surface' }; }
    if (s.status !== 'counted') {
      return { idle: false, reason: 'sessions surface ' + s.status + ': ' + reasonFor(d, s, 'sessions') };
    }
    var cur = s.detail && s.detail.current;
    if (!cur) { return { idle: false, reason: reasonFor(d, s, 'sessions') }; }
    var agents = cur.agents;
    if (agents === undefined || agents === null) { return { idle: true }; }
    if (Object.prototype.toString.call(agents) !== '[object Array]') {
      return { idle: false, reason: 'the recorded session view carries an agents field that is not an array' };
    }
    return { idle: agents.length === 0 };
  }

  function laneRows(d) {
    var s = surfaceOf(d, 'sessions');
    var cur = s && s.detail && s.detail.current;
    var rows = (cur && cur.agents) || [];
    var out = rows.slice(0);
    out.sort(function (a, b) {
      var ax = tsToEpoch(a && a.last_ts), bx = tsToEpoch(b && b.last_ts);
      if (ax === null && bx === null) { return 0; }
      if (ax === null) { return 1; }
      if (bx === null) { return -1; }
      return bx - ax;
    });
    return out;
  }

  function buildLane(id) {
    var li = document.createElement('li');
    li.className = 'lane';
    li.setAttribute('data-agent-id', id);
    li.innerHTML =
      '<div class="lane-head">' +
      '<span class="dot" data-role="dot"></span>' +
      '<span class="lane-name" data-role="name"></span>' +
      '<span class="chip" data-role="chip"></span>' +
      '<span class="lane-meta" data-role="meta"></span>' +
      '</div>' +
      '<div class="track"><div class="shuttle" data-role="shuttle"></div></div>';
    return li;
  }

  function renderLanes(d) {
    var host = el('lanes');
    if (!host) { return 0; }
    var rows = laneRows(d), i, r, id, li;
    var gen = (typeof d.generated_at_epoch === 'number') ? d.generated_at_epoch : null;
    var seen = {};

    for (i = 0; i < rows.length; i++) {
      r = rows[i] || {};
      id = String(r.agent_id || ('row-' + i));
      seen[id] = true;

      li = laneEls[id];
      if (!li) { li = buildLane(id); laneEls[id] = li; }
      host.appendChild(li);

      var typed = !!r.agent_type;
      var name = typed ? stripPrefix(r.agent_type) : null;
      var row = typed ? (renderLanes.roster || {})[name] : null;

      var lastEp = tsToEpoch(r.last_ts);
      var age = (gen !== null && lastEp !== null) ? (gen - lastEp) : null;
      var stalled = (age !== null && age > STALL_SEC);

      var evRaw = r.events;
      var ev = (typeof evRaw === 'number') ? evRaw : null;

      li.querySelector('[data-role="name"]').textContent = typed ? name : 'identity unknown';

      var chip = li.querySelector('[data-role="chip"]');
      if (typed) {
        chip.className = 'chip';
        chip.textContent = r.branch ? ('branch ' + r.branch) : ('agent ' + id);
        chip.title = 'agent_type ' + r.agent_type;
      } else {
        chip.className = 'chip unknown';
        chip.textContent = 'identity unknown';
        chip.title = 'no event for this agent_id carried an agent_type; the projector records no spawn event, so the role cannot be derived';
      }

      var dot = li.querySelector('[data-role="dot"]');
      dot.className = 'dot';
      if (row && row.read_only === true) { dot.classList.add('hollow'); }
      if (row && row.color) { dot.style.background = (row.read_only === true) ? 'transparent' : row.color; dot.style.borderColor = row.color; }
      else { dot.style.background = ''; dot.style.borderColor = ''; }

      var evTxt = (ev === null) ? '— events' : (ev + ' events');
      var meta = li.querySelector('[data-role="meta"]');
      if (stalled) {
        meta.textContent = evTxt + ' · no event for ' + fmtAge(age);
      } else {
        meta.textContent = evTxt + ' · last ' + (age === null ? 'unknown' : fmtAge(age));
      }
      meta.title = 'agent_id ' + id + (r.first_ts ? (' · first ' + r.first_ts) : '') + (r.last_ts ? (' · last ' + r.last_ts) : '');

      if (stalled) { li.classList.add('stalled'); li.classList.remove('pulse'); }
      else { li.classList.remove('stalled'); li.classList.add('pulse'); }

      /* THE ONLY MOTION. The shuttle advances only when this lane's recorded event count
       * changed since the previous render. Same count -> the transform is rewritten to the
       * same value -> no transition fires -> the lane is visually still. */
      var prev = Object.prototype.hasOwnProperty.call(prevEvents, id) ? prevEvents[id] : null;
      if (!Object.prototype.hasOwnProperty.call(shuttleStep, id)) { shuttleStep[id] = 0; }
      if (ev !== null && prev !== null && ev !== prev) { shuttleStep[id] = (shuttleStep[id] + 1) % 6; }
      prevEvents[id] = ev;
      li.querySelector('[data-role="shuttle"]').style.transform =
        'translateX(' + (shuttleStep[id] * 82 / 5) + '%)';
    }

    for (var k in laneEls) {
      if (Object.prototype.hasOwnProperty.call(laneEls, k) && !seen[k]) {
        if (laneEls[k].parentNode) { laneEls[k].parentNode.removeChild(laneEls[k]); }
        delete laneEls[k];
      }
    }

    var lc = el('lane-count');
    if (lc) { lc.textContent = rows.length ? ('(' + rows.length + ' in the newest session)') : ''; }
    return rows.length;
  }

  function renderRoster(d) {
    var host = el('roster');
    if (!host) { return; }
    var s = surfaceOf(d, 'agents');
    var rows = (s && s.detail && s.detail.roster) || [];
    host.innerHTML = '';
    var src = el('roster-src');
    if (src) {
      src.textContent = s ? ('(' + (s.status === 'counted' ? (rows.length + ' agents') : (s.status + ': ' + (s.reason || 'no reason recorded'))) + ')') : '(no agents surface)';
    }
    if (!rows.length) {
      var p = document.createElement('li');
      p.className = 'empty';
      p.textContent = 'no roster recorded';
      host.appendChild(p);
      return;
    }
    for (var i = 0; i < rows.length; i++) {
      var r = rows[i] || {};
      var li = document.createElement('li');
      var dot = document.createElement('span');
      dot.className = 'dot';
      if (r.read_only === true) { dot.classList.add('hollow'); dot.style.background = 'transparent'; }
      if (r.color) { dot.style.borderColor = r.color; if (r.read_only !== true) { dot.style.background = r.color; } }
      li.appendChild(dot);
      var nm = document.createElement('span');
      nm.textContent = ' ' + (r.name || 'unnamed');
      li.appendChild(nm);
      var meta = document.createElement('span');
      meta.className = 'r-meta';
      /* read_only is a TRI-STATE: the projector OMITS it when the agent file states no
       * disallowedTools at all. Absent is rendered as unknown, never as "not read-only". */
      var ro = (r.read_only === true) ? 'read-only'
        : (r.read_only === false) ? 'writes'
          : 'read-only unknown';
      meta.textContent = ' · ' + (r.model || 'model unknown') +
        ' · budget ' + (typeof r.max_turns === 'number' ? r.max_turns : 'unknown') +
        ' · ' + ro;
      li.appendChild(meta);
      host.appendChild(li);
    }
  }

  function renderNotes(d) {
    var host = el('notes');
    if (!host) { return; }
    host.innerHTML = '';
    var notes = (d && d.notes) || [];
    if (!notes.length) {
      var li0 = document.createElement('li');
      li0.className = 'empty';
      li0.textContent = 'no notes - every surface was counted';
      host.appendChild(li0);
      return;
    }
    for (var i = 0; i < notes.length; i++) {
      var li = document.createElement('li');
      li.textContent = String(notes[i]);
      host.appendChild(li);
    }
  }

  /* Freshness is judged against the wall clock and is recomputed on EVERY poll, because a
   * file that stopped being regenerated is exactly the condition this banner exists for.
   * This is a text update, not motion. */
  function renderFreshness(d, laneCount) {
    var gen = (d && typeof d.generated_at_epoch === 'number') ? d.generated_at_epoch : null;
    var g = el('generated');
    var nowSec = Math.floor(Date.now() / 1000);
    var age = (gen === null) ? null : (nowSec - gen);

    if (g) {
      g.textContent = (gen === null)
        ? 'floor.json records no generation time (the projector could not read the clock)'
        : ('floor.json generated ' + fmtAge(age) + ' ago · schema_version ' + (d.schema_version) +
          (d.repo_head ? (' · HEAD ' + d.repo_head) : ''));
    }

    if (age !== null && age > STALE_SEC) {
      /* The AGE is measured; the CAUSE is not. This page cannot see `serve --interval`, so it
       * says how old the document is and which threshold that was judged against, and leaves
       * the diagnosis to the reader. Asserting that the file has stopped being regenerated
       * would be FALSE on every legal `--interval` longer than a third of this threshold. */
      banner('floor.json is stale (' + fmtAge(age) + ') - older than the ' + STALE_SEC +
        's freshness threshold this page polls against; if the serve loop regenerates less ' +
        'often than that, reopen the page with ?stale=<seconds>');
      return;
    }
    if (!laneCount) {
      var v = sessionsVerdict(d);
      banner(v.idle ? 'no run in flight' : ('session data unavailable — ' + v.reason));
      return;
    }
    banner('');
  }

  function apply(d) {
    var gen = (d && typeof d.generated_at_epoch === 'number') ? d.generated_at_epoch : null;
    var changed = (gen === null) || (gen !== lastGen);
    if (changed) {
      lastGen = gen;
      renderLanes.roster = rosterIndex(d);
      renderStages(d);
      apply.lanes = renderLanes(d);
      renderRoster(d);
      renderRules(d);
      renderChurn(d);
      renderNotes(d);
    }
    renderFreshness(d, apply.lanes || 0);
  }
  apply.lanes = 0;

  function fail(text) {
    banner(text);
    var lc = el('lane-count');
    if (lc) { lc.textContent = ''; }
  }

  /* ONE REQUEST AT A TIME. An origin that accepts a connection and never answers would
   * otherwise let every tick of the poll add another outstanding fetch, and the page would
   * end up rendering whichever response settled last rather than the newest bytes. This is a
   * flag, not a second timer: the existing poll simply skips a tick while one is open, and
   * the flag is cleared on BOTH settle paths (and on a synchronous throw) so a single failure
   * can never wedge the page permanently. */
  var inFlight = false;

  /* THE STOPPED STATE IS A STATE, NOT AN ERROR. Once `stop` has been accepted, this origin is
   * going away, and a page that kept polling it would render a stream of fetch failures about
   * a server the reader deliberately stopped - or, worse, keep showing the last floor as if it
   * were current. The flag gates the poll instead: the one timer keeps ticking and does
   * nothing, which is why no second timer and no listener teardown are needed. */
  var serverStopped = false;

  /* THE ONE AND ONLY `fetch(` CALL SITE IN THIS FILE. Both documents the page reads go
   * through it, which is what keeps "exactly one request shape, relative, no-store, no method
   * option" a property that can be counted rather than reviewed. It RESOLVES on every HTTP
   * outcome, describing it, and rejects only when the request itself failed - so a caller
   * never has to tell "404" apart from "the origin vanished" by inspecting an exception. */
  function fetchText(url) {
    return fetch(url, { cache: 'no-store' }).then(function (r) {
      if (r.status === 404) { return { missing: true }; }
      if (!r.ok) { return { error: 'status ' + r.status }; }
      return r.text().then(function (t) { return { text: t }; });
    });
  }

  function poll() {
    if (serverStopped) { return; }
    if (inFlight) { return; }
    inFlight = true;
    try {
      /* CHAINED, NEVER CONCURRENT. The served index is read first because it decides WHICH
       * floor.json the second read asks for; the single in-flight flag spans both. */
      /* Which document the shared catch below should name. Set BEFORE each leg can reject,
         so a rejection is attributed to the read that actually failed rather than to
         whichever document the handler happened to be written about. */
      var failedDoc = SERVED_INDEX;
      fetchText(SERVED_INDEX).then(function (res) {
        var idx;
        if (res && res.missing) {
          idx = { absent: true };
        } else if (res && res.error) {
          idx = { absent: true, fetchError: res.error };
        } else {
          try { idx = JSON.parse(res.text); } catch (e) {
            idx = { absent: true, parseError: (e && e.message) || 'not valid JSON' };
          }
        }
        try { renderProjectPicker(idx); } catch (e) {
          /* A picker that throws must not take the floor down with it: the floor is the
             document this page exists to render, and it is already on its way. */
          var pn = el('project-note');
          if (pn) { pn.textContent = 'the served index was read but the picker could not be rendered (' + ((e && e.message) || 'render failed') + ')'; }
        }
        failedDoc = projectUrl(selectedSlug);
        return fetchText(projectUrl(selectedSlug));
      }).then(function (res) {
        inFlight = false;
        if (!res) { return; }
        if (res.missing) {
          fail('no floor.json at ' + projectUrl(selectedSlug) +
            ' — this origin holds no document for that project yet');
          return;
        }
        if (res.error) { fail('floor.json could not be read (' + res.error + ')'); return; }
        var d;
        try { d = JSON.parse(res.text); } catch (e) {
          fail('floor.json is present but is not valid JSON');
          return;
        }
        /* Render errors are NOT fetch errors. The document was served and parsed by the
           time we get here, so letting a throw from apply() fall through to the catch
           below would banner "no floor.json at this origin" about a file we just read -
           naming a cause the page has already disproved. Same discipline as the stale
           banner: state what was measured, never a cause that was not. */
        try { apply(d); } catch (e) {
          fail('floor.json was read but could not be rendered (' + ((e && e.message) || 'render failed') + ')');
        }
      })['catch'](function (e) {
        inFlight = false;
        /* poll() chains TWO fetches - the served index, then the selected project's floor.json -
           behind this one handler, so blaming floor.json unconditionally names a document that
           may have read fine. `failedDoc` is set by whichever leg actually rejected; the page
           states what it measured and nothing more, which is the same rule the stale banner and
           the render-failure branch above already follow. */
        fail('could not read ' + (failedDoc || 'floor.json') + ' at this origin (' + ((e && e.message) || 'fetch failed') + ')');
      });
    } catch (e) {
      /* Deliberately NOT failedDoc: this catch fires when the fetch could not even be
         STARTED, so no document has been attempted and naming one would be a guess. */
      inFlight = false;
      fail('the floor could not be requested at this origin (' + ((e && e.message) || 'fetch unavailable') + ')');
    }
  }

  /* The picker's change handler. An EVENT, not a timer: it fires because a human chose
   * something, and it re-polls immediately so the switch lands inside one poll interval
   * rather than up to one interval later. The lane memory is dropped first - see
   * resetProjectMemory - because it describes the document being left behind. */
  (function () {
    var sel = el('project-picker');
    if (!sel) { return; }
    sel.onchange = function () {
      pickerTouched = true;
      setSelectedSlug((sel.value === '') ? null : sel.value);
      banner('');
      poll();
    };
  }());

  /* ------------------------------------------------------------------------------------
   * THE FOUR ACTIONS
   *
   * Each button is an EVENT, never a schedule. A successful write re-polls the ONE existing
   * loop immediately, so the change lands inside one poll interval rather than up to one
   * interval later - the same shape the picker's change handler already uses, and the reason
   * no retry, debounce or "saved"-flash timer appears anywhere in this file.
   * ------------------------------------------------------------------------------------ */

  function actionNote(text) {
    var n = el('action-note');
    if (n) { n.textContent = text || ''; }
  }

  function actionReport(text) {
    var r = el('action-report');
    if (r) { r.textContent = text || ''; }
  }

  /* THE STOPPED RENDER. Four things a reader could otherwise be shown instead, and all four
   * would be lies: a spinner (nothing is coming), the last floor presented as current (it is a
   * snapshot of a server that no longer exists), a fetch error (the reader asked for this), or
   * an uncaught exception in the console. Say what happened, and say what the floor now is. */
  function renderStopped() {
    serverStopped = true;
    document.body.setAttribute('data-stopped', 'true');
    /* The word this banner must NOT reach for is the one that claims a running process: this
     page has never labelled anything on it that way and a stopped state is not the place to
     start. Say what was measured - the server was stopped, nothing is being fetched. */
    banner('this server was stopped from this page. Nothing below is being updated any more, and this page will not ask this origin for anything again — run `/ui serve` to start it again and open the new URL it prints.');
    var g = el('generated');
    if (g) {
      g.textContent = 'the server was stopped from this page — what is shown below is the last document it served, not a current one';
    }
    var lc = el('lane-count');
    if (lc) { lc.textContent = ''; }
    var sel = el('project-picker');
    if (sel) { sel.disabled = true; }
    var host = el('actions');
    if (host) {
      host.setAttribute('data-stopped', 'true');
      var controls = host.querySelectorAll('button, input');
      for (var i = 0; i < controls.length; i++) { controls[i].disabled = true; }
    }
    actionNote('stopped. There is nothing left at this origin to ask.');
  }

  /* runAction — the one place a button's outcome is turned into words. A refusal is reported by
   * its NAME, because the server names every one of them and a page that flattened them all to
   * "failed" would send the reader to fix the wrong thing. */
  function runAction(action, payload) {
    if (serverStopped) { return; }
    if (!floorToken) {
      actionNote('this page holds no token for this run, so the server would refuse the write. Open the URL `setup-ui.sh serve` printed — it carries the token in its #fragment — rather than a bare address.');
      actionReport('');
      return;
    }
    actionNote(action + ': asked the server…');
    postAction(action, payload).then(function (res) {
      var body = res.body || {};
      var reason = (typeof body.reason === 'string' && body.reason) ? body.reason : ('status ' + res.status);
      if (res.status === 403) {
        actionNote(action + ' was REFUSED by the server guard (' + reason + '). Reopen the page from the URL this run of `serve` printed.');
      } else if (res.status === 501) {
        actionNote(action + ' is not a route this server answers (501) — the page and the engine are different versions.');
      } else if (body.ok === true) {
        actionNote(action + ': done.');
        if (action === STOP_ACTION) { renderStopped(); }
      } else {
        actionNote(action + ' was refused: ' + reason);
      }
      actionReport(typeof body.report === 'string' ? body.report : res.text);
      /* Re-read immediately rather than waiting for the next tick — but only for the writes
       * that can have changed what the page shows. */
      if (body.ok === true && action !== STOP_ACTION) { poll(); }
    })['catch'](function (e) {
      actionNote(action + ' could not be sent to this origin (' + ((e && e.message) || 'request failed') + ')');
      actionReport('');
    });
  }

  (function () {
    var input = el('add-path');
    var pathValue = function () { return input ? String(input.value || '').replace(/^\s+|\s+$/g, '') : ''; };
    var wire = function (id, fn) {
      var b = el(id);
      if (b) { b.onclick = fn; }
    };
    wire('btn-add', function () { runAction('add', { path: pathValue() }); });
    wire('btn-scan', function () { runAction('scan', { path: pathValue(), confirm: false }); });
    wire('btn-scan-confirm', function () { runAction('scan', { path: pathValue(), confirm: true }); });
    wire('btn-forget', function () {
      if (selectedSlug === null || selectedSlug === '') {
        actionNote('choose a registered project in the picker above first — `forget` names one entry by its slug, and the root document is not one.');
        actionReport('');
        return;
      }
      runAction('forget', { slug: String(selectedSlug) });
    });
    wire('btn-stop', function () { runAction(STOP_ACTION, {}); });
  }());

  poll();
  /* The one and only timer on this page. It fetches; it does not animate. */
  setInterval(poll, POLL_MS);
}());
