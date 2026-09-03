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
 *
 * LIVENESS IS NEVER INFERRED. floor.json records events, not processes. No element on this
 * page is labelled with a word that would claim a running process; the permanent note under
 * the lanes says so on every render, and the self-test scans for those words by name.
 *
 * NETWORK: one relative fetch of `floor.json` against this page's own origin. Nothing else.
 */
'use strict';

(function () {
  var POLL_MS = 2000;

  /* Query parameters, all optional, all integers, all clamped to something sane.
   *   ?stall=<seconds>  how old a lane's last event may get before the lane reads stalled
   *   ?stale=<seconds>  how old floor.json itself may get before the page says so. It exists
   *                     so the committed fixtures (whose generated_at_epoch is necessarily in
   *                     the past) can be demonstrated without the stale banner swallowing the
   *                     view; the default is 3x the poll interval, per the requirement.
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
    var active = phase ? PHASE_STAGE[phase] : null;
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
        setCell(vid, { text: '—', title: phase ? ('the recorded phase is ' + phase) : 'no phase is recorded' });
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
        note.textContent = age + br + rs;
      }
    }
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
      banner('floor.json is stale (' + fmtAge(age) + ') - nothing has regenerated it');
      return;
    }
    if (!laneCount) {
      banner('no run in flight');
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

  function poll() {
    try {
      fetch('floor.json', { cache: 'no-store' }).then(function (r) {
        if (r.status === 404) { fail('no floor.json at this origin'); return null; }
        if (!r.ok) { fail('floor.json could not be read (status ' + r.status + ')'); return null; }
        return r.text();
      }).then(function (t) {
        if (t === null || t === undefined) { return; }
        var d;
        try { d = JSON.parse(t); } catch (e) {
          fail('floor.json is present but is not valid JSON');
          return;
        }
        apply(d);
      })['catch'](function (e) {
        fail('no floor.json at this origin (' + ((e && e.message) || 'fetch failed') + ')');
      });
    } catch (e) {
      fail('no floor.json at this origin (' + ((e && e.message) || 'fetch unavailable') + ')');
    }
  }

  poll();
  /* The one and only timer on this page. It fetches; it does not animate. */
  setInterval(poll, POLL_MS);
}());
