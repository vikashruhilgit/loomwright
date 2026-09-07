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
 * `Host` besides. The token comes out of the URL fragment `serve` printed - a fragment is never
 * sent to any server - and is stripped from the address bar immediately, so it cannot leak
 * through history, a bookmark or a shared screenshot. It is held for the life of the TAB, not
 * of one load: see the token block below for why one load was not enough.
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
  /* HOW OLD A LANE MAY BE AND STILL BE LISTED. A `cc_session_id` is not a unit of work — it
   * survives `/clear` and it survives resume, so one id can persist for days and accumulate
   * every agent that ever ran under it. Measured on a real project: one session's lanes spanned
   * FOUR DAYS, three of them last recorded on Sep 2 sitting beside three from the last minute.
   * Listing them together says "these are the current lanes" about work that ended days ago.
   * A lane with NO recorded ts is NOT old — it is unknown — so it is never filtered out here. */
  var LANE_SEC = qpInt('lane', 1800, 1);

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

  /* THE ABSOLUTE DIRECTORY OF THE DOCUMENT ON SCREEN, and the served index is the ONLY place
   * this page can learn it: floor.json carries no root of its own. The rules view joins a
   * repo-relative `applies_to` glob against it. It stays null whenever the index names no
   * directory for the current selection, so that view says it does not know the base rather
   * than inventing one. Set on every tick by renderProjectPicker, which runs before the floor
   * is rendered in the same tick. */
  var selectedPath = null;

  /* THE WRITE PATH'S THREE CONSTANTS, and all three are fixed strings in this file.
   * API_PREFIX is what makes the endpoint URLs a property of this code rather than of any
   * document it read: the same guarantee projectUrl already gives the read path. */
  var API_PREFIX = 'api/';
  var TOKEN_HEADER = 'X-Floor-Token';
  /* The ONE refusal of the guard's three that is actually about the token, named here as a
   * literal because the 403 branch below has to tell it apart from the other two rather than
   * treat every refusal as a dead credential. It is the server's own spelling. */
  var TOKEN_REFUSAL = 'token-missing-or-wrong';
  var STOP_ACTION = 'stop';

  /* THE PER-RUN TOKEN. It arrives in the URL FRAGMENT, which a browser never transmits to any
   * server, so it cannot appear in a request line, an access log, a proxy or a referrer. The
   * fragment is removed from the address bar the moment it is read, because the address bar is
   * exactly what ends up in history, in a bookmark and in a screenshot.
   *
   * THAT STRIP USED TO BE THE WHOLE STORY, AND IT MADE THE TOKEN SURVIVE EXACTLY ONE LOAD.
   * Every ordinary way of arriving back at this page then arrived without it - a reload, a
   * bookmark, an omnibox completion (which can only ever offer the STRIPPED url, because the
   * strip is precisely what put that url in history), a restored session - and each one
   * dropped the reader into read-only silently, while the refusal blamed them for opening "a
   * bare address" they had not typed. Two additions, neither of which gives up any property
   * claimed above:
   *
   *   - sessionStorage, so a RELOAD of this tab keeps the token. It is per-origin and per-tab,
   *     it never reaches a url, a server or another tab, and it dies with the tab - the same
   *     lifetime the closure variable already had, minus the reload.
   *   - a `hashchange` listener, so a token appended to the url of a page ALREADY OPEN is
   *     picked up. Adding a fragment to the url a tab is already on is a same-document
   *     navigation: nothing reloads, this script never runs again, and pasting the printed url
   *     into the tab already showing this page therefore did nothing whatsoever. That is the
   *     likeliest way a reader reaches the refusal, and it now works.
   *
   * A STALE token is the one thing the store can hand back that a fragment never could, since
   * it survives the SERVER and not merely the load. So a 403 from the guard CLEARS it (see
   * runAction) rather than letting the page replay a dead credential on every click.
   * An empty token is a legitimate state, not an error: the page still READS everything. Only
   * the four buttons are refused, and they say why rather than failing silently. */
  var TOKEN_STORE_KEY = 'loomwright.floor.token';
  var floorToken = '';

  /* EVERY sessionStorage touch is wrapped. A browser in a private mode, or one configured to
   * refuse site data, throws on the property access itself rather than returning null - and a
   * page that died there would have lost the READ path too, over a convenience. */
  function storeToken(t) {
    try { window.sessionStorage.setItem(TOKEN_STORE_KEY, t); } catch (e) { /* memory-only, as before */ }
  }
  function storedToken() {
    try { return String(window.sessionStorage.getItem(TOKEN_STORE_KEY) || ''); } catch (e) { return ''; }
  }
  /* Called only when the SERVER says the token is no good. Dropping it here is what stops a
   * token left over from a previous run being replayed on every subsequent click. */
  function dropToken() {
    floorToken = '';
    try { window.sessionStorage.removeItem(TOKEN_STORE_KEY); } catch (e) { /* nothing to drop */ }
  }
  function fragmentToken() {
    var m = /(?:^#|[#&])token=([A-Za-z0-9_-]+)/.exec(String(window.location.hash || ''));
    return m ? m[1] : '';
  }
  /* THE STRIP, ON ITS OWN, because it has two callers and only one of them adopts anything.
   * The file's stated invariant is that the fragment leaves the address bar the moment it is
   * read - and that has to hold for a token this page ALREADY holds, not only for a new one.
   * Pasting the same url a second time (a habit a reader picks up precisely because the first
   * paste used to do nothing) took the `t === floorToken` early return below and never reached
   * the strip, so the token stayed in the address bar and went to history from there. */
  function stripFragment() {
    if (window.history && window.history.replaceState) {
      try {
        window.history.replaceState(null, '', window.location.pathname + (window.location.search || ''));
      } catch (e) {
        /* A browser that refuses the rewrite must not take the page down with it: the token is
         * already held by the caller, and the only cost is a url that still shows it. */
      }
    }
  }

  /* Read, remember, THEN erase from the address bar - in that order, because the strip must not
   * happen until the token is held somewhere that survives the address bar. */
  function adoptToken(t) {
    floorToken = t;
    storeToken(t);
    stripFragment();
  }

  (function () {
    var t = fragmentToken();
    if (t) { adoptToken(t); return; }
    /* No fragment on this load. A token THIS TAB adopted earlier is the honest fallback: same
     * tab, same origin, same browsing session - which is the reload case this exists for. */
    floorToken = storedToken();
  }());

  /* THE SAME-DOCUMENT CASE, and the reason it needs an event at all: changing only the fragment
   * reloads nothing, so without this listener the paste is inert. `replaceState` does not fire
   * `hashchange`, so adoptToken's own strip cannot re-enter here. */
  window.addEventListener('hashchange', function () {
    var t = fragmentToken();
    if (!t) { return; }
    /* ALREADY HELD. There is nothing to adopt and nothing to announce - but the address bar is
     * showing a token, and this page's whole claim about fragments is that it does not leave
     * one there. Strip and say nothing. */
    if (t === floorToken) { stripFragment(); return; }
    adoptToken(t);
    actionNote('token accepted from the url — the four buttons will now be accepted for this run.');
  });

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
      selectedPath = null;
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

    /* Recomputed every tick from the rows this render just drew, and AFTER the block above,
     * because that block is where selectedSlug can still change (the first build's choice, and
     * the follow-it branch when the viewed project leaves the registry). */
    selectedPath = null;
    if (selectedSlug === null || selectedSlug === '') {
      if (typeof srv.selected_path === 'string' && srv.selected_path) { selectedPath = srv.selected_path; }
    } else {
      for (i = 0; i < rows.length; i++) {
        if (rows[i] && String(rows[i].slug) === String(selectedSlug)
            && typeof rows[i].path === 'string' && rows[i].path) {
          selectedPath = rows[i].path;
          break;
        }
      }
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
    /* The rules view's copy note names an absolute path under the project that was on screen
     * when it was written. Carrying it across a switch would leave one project's path standing
     * under another project's rules - a statement about a document nobody is looking at. */
    pathNote('');
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
        /* THE CELL NO LONGER REPEATS ITS OWN LABEL. `EXECUTE` in the cell headed `Execute` read
         * as "Execute EXECUTE" — the value slot had nothing to say that the label had not
         * already said. Where the recorded phase and the stage name coincide the cell carries a
         * marker; where they differ (FINALIZE and SELF_HEAL both map to Review) the word is
         * information and is kept. The phase is stated in full in the note below either way. */
        setCell(vid, {
          text: (String(phase).toUpperCase() === mids[i].toUpperCase()) ? '●' : phase,
          title: 'state.detail.phase, as recorded in .supervisor/state.md'
        });
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
        /* WHOSE PHASE THIS IS. `state.md` is one repo-global file and it records the session
         * that owns it, so a phase shown without that owner invites the reader to attach it to
         * whatever session the lanes below happen to be. Name it. */
        var owner = (state.detail && typeof state.detail.session_id === 'string' && state.detail.session_id)
          ? (' · phase recorded by session ' + state.detail.session_id.slice(0, 8)) : '';
        var ph = unmapped
          ? (' · recorded phase ' + phase + ' — no pipeline stage corresponds to it')
          : (phase ? '' : ' · no phase is recorded');
        note.textContent = age + br + rs + owner + ph;
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

  /* THE GLOBS IN A SCOPE HEADING ARE COPYABLE, AND DELIBERATELY NOT LINKS.
   *
   * The obvious affordance for a path is an anchor, and this page cannot honour one: every
   * current browser refuses to follow a `file:` URL from a document served over http, and it
   * refuses SILENTLY - no navigation, no error the reader sees. A control that looks like it
   * opens a file and does nothing is the same defect class as a count rendered `0` for a
   * surface nobody read, so the control says what it actually does. Serving the file instead is
   * not on the table either: that would be a fifth endpoint, and the four are closed by
   * decision (docs/FLOOR_UI.md §"Why the guard exists").
   *
   * NO NEW TIMER. The note persists until the next click or a project switch; a "copied!" flash
   * that cleared itself would be the second timer this file does not have.
   *
   * THE HEADING TEXT IS UNCHANGED. `ruleScopeLabel` still decides the grouping key and still
   * decides what a heading says - the chips are only permitted when they spell that exact
   * string back (the equality below), so a malformed or non-array `applies_to` keeps its own
   * label and gains no clickable anything. */
  var SCOPE_PREFIX = 'scoped to ';

  /* The globs BEHIND a 'scoped to …' heading, or null when the value is not the shape that
   * heading was built from. All-or-nothing on purpose: `join` stringifies a non-string element
   * silently, and one chip carrying `[object Object]` is worse than a plain heading. */
  function scopeGlobs(r) {
    /* NO PRESENCE CHECK HERE, deliberately, and for two reasons. The tri-state that key
     * presence decides belongs to `ruleScopeLabel`, which owns what a heading SAYS; this
     * function asks only "is this the non-empty array of non-empty strings that heading was
     * built from", and an absent key answers that with `undefined`, which is not an array.
     * And a second presence check spelled the same way as the one above would let the suite's
     * (j4) literal survive the mutant (j7) builds out of ruleScopeLabel's own guard - the
     * assertion would then pass on THIS line while the guard it names had been removed. That
     * is why the spelling is avoided here even in a comment: has_lit greps the file, not the
     * code, so a comment quoting the literal keeps the mutant green just as well. */
    var v = r && r.applies_to, out = [], i;
    if (Object.prototype.toString.call(v) !== '[object Array]' || !v.length) { return null; }
    for (i = 0; i < v.length; i++) {
      if (Object.prototype.toString.call(v[i]) === '[object String]' && v[i]) { out.push(v[i]); }
    }
    return out.length === v.length ? out : null;
  }

  function pathNote(msg) {
    var n = el('rules-path-note');
    if (n) { n.textContent = msg; }
  }

  /* What a chip does when clicked. The absolute form is joined HERE, from the directory the
   * served index names for the document on screen, and the note NAMES that base - so a project
   * registered below its git root (which is where build-floor.sh runs, and where the glob is
   * really rooted) shows the discrepancy instead of hiding it. With no base the rule's own
   * recorded text is copied and the note says that is what happened. */
  function copyScopePath(glob) {
    var base = selectedPath;
    var abs = base ? (base.replace(/\/+$/, '') + '/' + glob) : glob;
    var isGlob = /[*?[]/.test(glob);
    var kind = isGlob ? 'glob — it names a set of paths, not one file' : 'path';
    var where = base
      ? ' — joined against ' + base + ', the directory the served index names for the document on screen'
      : ' — the served index names no directory for the document on screen, so this is the text the rule itself records';
    var tail = where + ' (' + kind + ')';
    /* `navigator.clipboard` exists on this origin because 127.0.0.1 is a secure context, but a
     * page opened under some other hostname would not have it, and the API can refuse. Say so;
     * the note carries the path either way, so it can still be selected by hand. */
    if (!navigator.clipboard || typeof navigator.clipboard.writeText !== 'function') {
      pathNote(abs + tail + '. This browser exposes no clipboard to this page, so nothing was copied — select it here and copy it by hand.');
      return;
    }
    navigator.clipboard.writeText(abs).then(function () {
      pathNote('copied ' + abs + tail + '.');
    }, function (e) {
      pathNote(abs + tail + '. The clipboard refused it (' + ((e && e.message) || 'no reason given') +
        '), so nothing was copied — select it here and copy it by hand.');
    });
  }

  function renderScopeHeading(label, sample) {
    var h4 = document.createElement('h4');
    h4.className = 'rules-scope';
    var globs = scopeGlobs(sample);
    /* The chips must spell the heading they replace, or the heading wins. */
    if (!globs || (SCOPE_PREFIX + globs.join(', ')) !== label) {
      h4.textContent = label;
      return h4;
    }
    h4.appendChild(document.createTextNode(SCOPE_PREFIX));
    for (var i = 0; i < globs.length; i++) {
      if (i) { h4.appendChild(document.createTextNode(', ')); }
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'scope-path';
      b.textContent = globs[i];
      b.title = 'copy this path — a browser will not open a local file from a page served over http, so this copies it instead';
      b.onclick = (function (g) { return function () { copyScopePath(g); }; }(globs[i]));
      h4.appendChild(b);
    }
    return h4;
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
        /* The heading is built from the label AND from one rule that produced it: the label is
         * what the reader reads, and the rule is where the individual globs are recorded. */
        body.appendChild(renderScopeHeading(scopeOrder[si], byScope[scopeOrder[si]][0]));

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
            /* ONE ROW PER LEDGER LINE - not one per match. `matched` is one entry per
             * (line, path, pattern) triple, but the evidence is a property of the LINE, so a rule
             * whose globs match many paths on the same line re-printed the identical evidence
             * string once per path. Measured on this repo's own store: 347 rendered rows for 153
             * (rule, line) facts over 79 distinct ledger lines, with one line rendered 19 times.
             *
             * The projector already fixed the WIRE form of exactly this - it hoisted evidence out
             * of `matched` into `evidence_by_line` keyed by line (build-floor.sh, "EVIDENCE IS
             * CARRIED ONCE PER CORRELATION, KEYED BY LINE") - but this renderer kept re-joining it
             * onto every match, so the bytes were de-duplicated and the pixels never were. That is
             * the half this closes; the artefact's shape is untouched.
             *
             * NOTHING HERE IS ORDERED BY COUNT, the same order-by-key discipline the rest of this
             * surface holds to. Lines come out in encounter order, which the projector sorts by
             * [line, path, pattern] and so is ascending by line; the pattern groups inside a line
             * are ordered by pattern KEY. */
            var lineOrder = [], byLine = {}, m, mm, lineKey;
            for (m = 0; m < matched.length; m++) {
              mm = matched[m] || {};
              lineKey = String(mm.line);
              if (!Object.prototype.hasOwnProperty.call(byLine, lineKey)) {
                byLine[lineKey] = []; lineOrder.push(lineKey);
              }
              byLine[lineKey].push(mm);
            }
            for (var gi = 0; gi < lineOrder.length; gi++) {
              var group = byLine[lineOrder[gi]];
              var liEv = document.createElement('li');
              /* Evidence is carried ONCE PER CORRELATION in `evidence_by_line`, keyed by line -
               * `matched[].line` is the key into it. This branch used to read `mm.evidence`, which
               * the projector stopped emitting when the evidence was hoisted to kill a ~4x
               * duplication; the read was not updated, so the branch was DEAD for every artefact
               * the current projector can produce and every correlation rendered as a label and a
               * basis with nothing under it - while three doc surfaces claimed the evidence was
               * shown. The `mm.evidence` fallback is kept for an artefact produced BEFORE the
               * hoist, which schema_version 1 still makes legal - and because a legacy artefact
               * carries it per MATCH, the group is scanned for the first match that has any. */
              var evList = null;
              for (m = 0; m < group.length && evList === null; m++) {
                if (group[m].evidence && group[m].evidence.length) { evList = group[m].evidence; }
              }
              if (evList === null) { evList = (rc.evidence_by_line || {})[lineOrder[gi]] || []; }

              /* A line with exactly ONE match keeps the original single-row wording verbatim:
               * there is no duplication to collapse there, and the path/pattern pair IS the row's
               * content. Only a line that actually repeated gets the collapsed header. */
              var evTxt = (group.length === 1)
                ? 'line ' + group[0].line + ' · ' + group[0].path + ' matched ' + group[0].pattern
                : 'line ' + group[0].line + ' · ' + group.length + ' matches';
              if (evList.length) { evTxt += ' — evidence: ' + evList.join('; '); }
              else { evTxt += ' — no evidence recorded for this line'; }
              liEv.textContent = evTxt;

              /* The paths are NOT dropped - they move to one subordinate line PER PATTERN, so a
               * reader can still check which glob claimed which path. Per pattern, not per path:
               * a line's patterns are bounded by the rule's own applies_to (2 today), while its
               * paths are bounded by the commit (19 on the worst line here). */
              if (group.length > 1) {
                var patOrder = [], byPat = {}, patKey;
                for (m = 0; m < group.length; m++) {
                  patKey = String(group[m].pattern);
                  if (!Object.prototype.hasOwnProperty.call(byPat, patKey)) {
                    byPat[patKey] = []; patOrder.push(patKey);
                  }
                  byPat[patKey].push(group[m].path);
                }
                patOrder.sort();
                for (var p = 0; p < patOrder.length; p++) {
                  var paths = byPat[patOrder[p]];
                  var pathP = document.createElement('p');
                  pathP.className = 'corr-paths';
                  pathP.textContent = 'matched ' + patOrder[p] + ' → '
                    + (paths.length === 1
                        ? paths[0]
                        : paths.length + ' paths: ' + paths.join(', '));
                  liEv.appendChild(pathP);
                }
              }
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

  /* Split the sorted rows into what is listed and what was dropped for age. Returned as a pair
   * rather than filtered in place, because the count of omitted lanes has to be RENDERED: a lane
   * that silently vanishes is indistinguishable from one that never existed, which is the same
   * absent-vs-zero rule the count cells follow. */
  function laneSplit(d, gen) {
    var all = laneRows(d), keep = [], dropped = 0, i, ep, age;
    for (i = 0; i < all.length; i++) {
      ep = tsToEpoch(all[i] && all[i].last_ts);
      age = (gen !== null && ep !== null) ? (gen - ep) : null;
      if (age !== null && age > LANE_SEC) { dropped++; } else { keep.push(all[i]); }
    }
    return { rows: keep, dropped: dropped, total: all.length };
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
    var gen = (typeof d.generated_at_epoch === 'number') ? d.generated_at_epoch : null;
    var split = laneSplit(d, gen);
    var rows = split.rows, i, r, id, li;
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

      /* TWO REASONS FOR A MISSING ROLE, AND ONLY ONE OF THEM IS IGNORANCE. `agent_scope`
       * is recorded by the emitters from the transcript path the hook payload itself
       * carried: `main` means that path was the transcript of the SESSION, not a
       * `subagents/agent-<id>.jsonl` one, so the row is the session's own thread - a
       * lane with no agent role because it is not an agent. Calling that "identity
       * unknown" was the page reporting its own question as a missing answer.
       * `subagent` (a spawned agent whose payload carried no type) and an ABSENT scope
       * (nothing was provable either way) both keep the unknown label: they are the
       * cases where the identity really is not known. */
      var mainThread = !typed && r.agent_scope === 'main';

      var lastEp = tsToEpoch(r.last_ts);
      var age = (gen !== null && lastEp !== null) ? (gen - lastEp) : null;
      var stalled = (age !== null && age > STALL_SEC);

      /* "NO EVENTS RECORDED", never "not yet". The first wording said `yet`, which promises
       * events that are coming — and for an agent type with no SubagentStop emitter registered
       * they never were. Measured on a real run before that gap was closed: of the five types on
       * screen, three (plan-reviewer, rubric-grader and Claude Code's own general-purpose) could
       * not emit at all, so their lanes read "…yet" permanently. The emitters now cover every
       * agent this plugin ships; `general-purpose` still cannot, because it is not ours to
       * register a matcher for. So the honest sentence states what is recorded and stops. */
      var evRaw = r.events;
      var ev = (typeof evRaw === 'number') ? evRaw : null;

      li.querySelector('[data-role="name"]').textContent =
        typed ? name : (mainThread ? 'main thread' : 'identity unknown');

      var chip = li.querySelector('[data-role="chip"]');
      if (typed) {
        chip.className = 'chip';
        chip.textContent = r.branch ? ('branch ' + r.branch) : ('agent ' + id);
        chip.title = 'agent_type ' + r.agent_type;
      } else if (mainThread) {
        chip.className = 'chip';
        chip.textContent = r.branch ? ('branch ' + r.branch) : ('agent ' + id);
        chip.title = 'agent_scope main - every event for this agent_id came from a payload naming the transcript of the session itself, not a spawned agent transcript, so this lane is the session thread and has no agent role to report';
      } else {
        chip.className = 'chip unknown';
        chip.textContent = 'identity unknown';
        chip.title = 'no event for this agent_id carried an agent_type, and none carried an agent_scope that identifies the thread either, so the role cannot be derived';
      }

      var dot = li.querySelector('[data-role="dot"]');
      dot.className = 'dot';
      if (row && row.read_only === true) { dot.classList.add('hollow'); }
      if (row && row.color) { dot.style.background = (row.read_only === true) ? 'transparent' : row.color; dot.style.borderColor = row.color; }
      else { dot.style.background = ''; dot.style.borderColor = ''; }

      /* THE OTHER HALF OF THE READ-ONLY CUE. floor.css states the page-wide rule as
       * "read-only agent -> hollow dot + the text 'read-only'", and this view used to render
       * the dot ALONE: a read-only lane was distinguishable by SHAPE only, which is the
       * colour-is-never-the-only-signal rule broken in the one view that shows a run. The
       * words are renderRoster's own, reused rather than reinvented, and so is the TRI-STATE:
       *   true    -> say "read-only";
       *   false   -> say nothing here, because a writing agent is the unremarkable case and
       *              renderRoster's 'writes' belongs to a column this one-line meta lacks;
       *   neither -> a roster row that OMITS the key, and equally a lane with NO roster row at
       *              all, is reported as UNKNOWN rather than silently as "not read-only" -
       *              the same refusal renderRoster already makes, for the same reason.
       * The condition mirrors the dot's above exactly, so the shape and the words can never
       * disagree about the same agent. */
      /* The main thread is the ONE case that leaves this tri-state, and not by relaxing
       * it: the roster describes the agents this plugin ships, and the session thread is
       * not one of them, so there is no roster row here to be missing. Reporting
       * "read-only unknown" would answer a question that does not apply, which is a
       * different error from the one the tri-state exists to prevent. */
      var roTxt = (row && row.read_only === true) ? 'read-only'
        : (row && row.read_only === false) ? ''
          : mainThread ? ''
            : 'read-only unknown';
      var roSuffix = roTxt ? (' · ' + roTxt) : '';

      var evTxt = (ev === null) ? '— events' : (ev + ' events');
      var meta = li.querySelector('[data-role="meta"]');
      if (stalled) {
        meta.textContent = evTxt + ' · no event for ' + fmtAge(age) + roSuffix;
      } else {
        meta.textContent = (ev === 0)
          ? ('spawned, no events recorded' + roSuffix)
          : evTxt + ' · last ' + (age === null ? 'unknown' : fmtAge(age)) + roSuffix;
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
    if (lc) {
      lc.textContent = split.total
        ? ('(' + rows.length + ' of ' + split.total +
           (split.dropped ? (' · ' + split.dropped + ' with no event for over ' + fmtAge(LANE_SEC) + ' not listed') : '') + ')')
        : '';
    }
    return rows.length;
  }

  /* THE SESSION THIS PAGE IS SHOWING, and why it is that one. Rendered from recorded fields
   * only: the branch the session's own lines carried, its cc_session_id, and the projector's
   * `selection`. `newest_recorded` is the FAIL-OPEN case — no session qualified as plugin work,
   * so the newest recorded one is shown and the reader is TOLD, rather than being shown nothing.
   * `sessions_not_plugin_work` is the count set aside, printed because a session silently
   * excluded is indistinguishable from one that was never recorded. */
  function renderSessionNote(d) {
    var n = el('session-note');
    if (!n) { return; }
    var s = surfaceOf(d, 'sessions');
    var cur = s && s.detail && s.detail.current;
    if (!cur || typeof cur.cc_session_id !== 'string') { n.textContent = ''; return; }
    var bits = ['showing session ' + cur.cc_session_id.slice(0, 8)];
    if (typeof cur.branch === 'string' && cur.branch) { bits.push('branch ' + cur.branch); }
    if (cur.selection === 'plugin_run') {
      bits.push('chosen because it recorded plugin work, not because it is the most recent');
    } else if (cur.selection === 'newest_recorded') {
      bits.push('no session recorded plugin work, so this is simply the most recent one — it may be a Claude Code session you are working in directly');
    }
    if (typeof cur.sessions_not_plugin_work === 'number' && cur.sessions_not_plugin_work > 0) {
      bits.push(cur.sessions_not_plugin_work + ' other session(s) recorded no plugin work and are not shown');
    }
    n.textContent = bits.join(' · ');
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
      renderSessionNote(d);
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

  /* THE ONE PLACE THE ACTION CONTROLS ARE ENABLED OR DISABLED. Two callers need it - the
   * stopped render, permanently, and the write guard below, for the length of one request -
   * and a second, hand-rolled copy of "what the controls are" is how the two would come to
   * disagree about which of them counts. One selector, one loop, one caller-supplied flag. */
  function setActionsDisabled(flag) {
    var host = el('actions');
    if (!host) { return; }
    var controls = host.querySelectorAll('button, input');
    for (var i = 0; i < controls.length; i++) { controls[i].disabled = flag; }
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
    /* The dimming is the `data-stopped` attribute set on the BODY one line above, and only
     * that one. floor.css reaches `.lanes` and `.projects` through an ANCESTOR carrying the
     * attribute; #actions is a SIBLING of both, so a second copy of it there matched nothing
     * and has been removed rather than left to read as the thing doing the work. */
    setActionsDisabled(true);
    actionNote('stopped. There is nothing left at this origin to ask.');
  }

  /* ONE WRITE AT A TIME, for the same reason and in the same shape as the read poll's
   * `inFlight` flag above - a flag, never a second timer. The read path has held that guard
   * since it existed; the write path did not, and the gap was reachable by a reader rather
   * than only by a hung origin: each of the four buttons could be fired again while its own
   * request was still open, so one double-click put two `add` / `scan --confirm` / `forget`
   * requests on the wire at once against a registry that is a single file.
   * ITS HONEST LIMIT, stated because the fix does not reach it: this is a per-PAGE flag, and
   * it therefore says nothing about the same URL opened in a SECOND TAB - two documents, two
   * closures, and only the server sees both. What it closes is every re-entry inside one
   * page. Disabling the buttons is the visible half; the flag is what actually refuses the
   * second call, because a control can be re-enabled by anything with a console. */
  var writeInFlight = false;

  /* Cleared on EVERY exit - success, refusal, rejected request and a request that could not
   * be started at all - because a button left permanently disabled by one failed write is a
   * defect of its own, and a worse one than the double-click it was guarding against. The one
   * thing it must not undo is the stopped render: those controls are disabled for good, and
   * re-enabling them would offer writes this origin can no longer accept. */
  function releaseWrite() {
    writeInFlight = false;
    if (!serverStopped) { setActionsDisabled(false); }
  }

  /* runAction — the one place a button's outcome is turned into words. A refusal is reported by
   * its NAME, because the server names every one of them and a page that flattened them all to
   * "failed" would send the reader to fix the wrong thing. */
  function runAction(action, payload) {
    if (serverStopped) { return; }
    if (writeInFlight) { return; }
    if (!floorToken) {
      /* NAME THE THING THE READER ACTUALLY DID. The old wording said "rather than a bare
       * address", which reads as an accusation of typing one - and the commonest way to land
       * here never involved typing anything: an omnibox completion, a bookmark or a restored
       * session hands back the STRIPPED url on its own. Say where the token comes from and
       * what to do, and name the exit that needs no token at all. */
      actionNote('this page holds no token for this run, so the server would refuse the write — nothing was sent. `setup-ui.sh serve` prints the token once, in the #fragment of the url it prints: paste that whole url into this tab and press Enter, and this page will pick it up. Each of these four buttons also has a command-line verb — add, forget, scan, stop — that needs no token.');
      actionReport('');
      return;
    }
    writeInFlight = true;
    setActionsDisabled(true);
    actionNote(action + ': asked the server…');
    try {
      postAction(action, payload).then(function (res) {
        releaseWrite();
        var body = res.body || {};
        var reason = (typeof body.reason === 'string' && body.reason) ? body.reason : ('status ' + res.status);
        if (res.status === 403) {
          /* THE ONE PLACE A HELD TOKEN IS THROWN AWAY, and it is the server's word that does
           * it, never a guess on this side. A token can now survive the run that minted it -
           * sessionStorage survives the server, which the fragment never did - so without this
           * the page would replay a dead credential on every click and report the same 403
           * forever. Cleared, the NEXT click gets the honest no-token message and its remedy.
           *
           * BUT ONLY FOR THE REFUSAL THAT IS ABOUT THE TOKEN. The guard answers 403 for THREE
           * distinct reasons and names which in the body: the token, the `Origin`, or the
           * `Host`. Discarding on all three threw away a token that was very likely fine -
           * an extension or a proxy rewriting a header is not a stale credential - and then
           * told the reader a specific and wrong story about a previous run, sending them to
           * re-paste a url that reproduces the identical refusal. The server already draws
           * this distinction; the page now reads it instead of flattening it. */
          if (reason === TOKEN_REFUSAL) {
            dropToken();
            actionNote(action + ' was REFUSED by the server guard (' + reason + '). That token is now discarded — it was almost certainly minted by a PREVIOUS run of `serve`, since the token dies with its server. Run `setup-ui.sh check` for this run\'s url, paste it into this tab and press Enter.');
          } else {
            /* The token is KEPT, because nothing here said anything about it. */
            actionNote(action + ' was REFUSED by the server guard (' + reason + '). This is not about the token, so it has been kept — the server refused the request\'s Origin or Host, which is what a browser extension or a proxy rewriting those headers looks like. Re-pasting the url will reproduce it.');
          }
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
        releaseWrite();
        actionNote(action + ' could not be sent to this origin (' + ((e && e.message) || 'request failed') + ')');
        actionReport('');
      });
    } catch (e) {
      /* The request could not even be STARTED. Same discipline as the poll's outer catch, and
       * the reason this branch exists at all is the guard: without it a synchronous throw here
       * would leave the flag raised and every button dead for the rest of the page's life. */
      releaseWrite();
      actionNote(action + ' could not be requested at this origin (' + ((e && e.message) || 'request unavailable') + ')');
      actionReport('');
    }
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
