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
 * NETWORK: one relative fetch of `floor.json` against this page's own origin. Nothing else,
 * and never two at once - the poll holds an in-flight flag so a hung origin cannot stack
 * requests, cleared on both settle paths of that single request.
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

  function poll() {
    if (inFlight) { return; }
    inFlight = true;
    try {
      fetch('floor.json', { cache: 'no-store' }).then(function (r) {
        if (r.status === 404) { fail('no floor.json at this origin'); return null; }
        if (!r.ok) { fail('floor.json could not be read (status ' + r.status + ')'); return null; }
        return r.text();
      }).then(function (t) {
        inFlight = false;
        if (t === null || t === undefined) { return; }
        var d;
        try { d = JSON.parse(t); } catch (e) {
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
        fail('no floor.json at this origin (' + ((e && e.message) || 'fetch failed') + ')');
      });
    } catch (e) {
      inFlight = false;
      fail('no floor.json at this origin (' + ((e && e.message) || 'fetch unavailable') + ')');
    }
  }

  poll();
  /* The one and only timer on this page. It fetches; it does not animate. */
  setInterval(poll, POLL_MS);
}());
