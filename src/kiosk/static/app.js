/* Radio Kiosk — Frontend controller */
(function () {
  'use strict';

  var cfg   = {};
  var state = {};
  var qrBuilt = false;
  var currentScreen = 'main-screen';

  function qs(sel) { return document.querySelector(sel); }

  // ── Screen transitions ────────────────────────────────────────────────
  function showScreen(id) {
    if (currentScreen === id) return;
    currentScreen = id;
    document.querySelectorAll('.screen').forEach(function(s) {
      s.classList.toggle('active', s.id === id);
    });
  }

  // ── Clock ─────────────────────────────────────────────────────────────
  function pad(n) { return ('0' + n).slice(-2); }
  function updateClock() {
    var el = qs('#clock');
    if (!el) return;
    var d  = new Date();
    var h  = d.getHours(), m = d.getMinutes();
    var ap = h >= 12 ? 'PM' : 'AM';
    h = h % 12 || 12;
    el.innerHTML = pad(h) + ':' + pad(m) +
      '<span style="font-size:0.32em;margin-left:0.15em;vertical-align:super;opacity:0.55;">' + ap + '</span>';
  }

  // ── Apply config to DOM ───────────────────────────────────────────────
  function applyConfig(c) {
    cfg = c || {};
    var st   = cfg.station  || {};
    var disp = cfg.display  || {};

    // Theme
    document.body.className = disp.theme === 'light' ? 'light' : '';

    // Rotation
    var rot = parseInt(disp.rotation || 0, 10);
    if (rot) document.body.classList.add('rotate-' + rot);

    // Clock
    var clockEl = qs('#clock');
    if (clockEl) clockEl.style.display = disp.show_clock === false ? 'none' : '';

    // Logo image vs text fallback
    var logoImg  = qs('#logo-img');
    var logoText = qs('#logo-text');
    if (st.logo_url) {
      logoImg.src = st.logo_url;
      logoImg.classList.remove('hidden');
      logoImg.onerror = function() {
        logoImg.classList.add('hidden');
        logoText.textContent = st.name || '';
      };
    } else {
      if (logoImg) logoImg.classList.add('hidden');
      if (logoText) logoText.textContent = st.name || '';
    }

    // Accent colour
    if (st.accent_color) {
      document.documentElement.style.setProperty('--accent', st.accent_color);
    }

    // Tagline
    var tgEl = qs('#tagline');
    if (tgEl) {
      tgEl.textContent  = st.tagline || '';
      tgEl.style.display = st.tagline ? '' : 'none';
    }

    // Website URL (strip protocol)
    var urlEl = qs('#station-url');
    if (urlEl) urlEl.textContent = (st.website_url || '').replace(/^https?:\/\//, '');

    // QR code (build once)
    var qrSec = qs('#qr-section');
    var qrEl  = qs('#qr-code');
    if (disp.show_qr_code === false || !st.qr_target) {
      if (qrSec) qrSec.style.display = 'none';
    } else if (qrEl && !qrBuilt) {
      var sz = Math.round(Math.min(window.innerHeight * 0.16, 124));
      makeQR(qrEl, st.qr_target, sz);
      qrBuilt = true;
    }
  }

  // ── Apply now-playing state to DOM ────────────────────────────────────
  function applyState(s) {
    state = s || {};
    var npEnabled = s.nowplaying_enabled;
    var hasTrack  = npEnabled && (s.title || s.artist);

    // Switch between now-playing and idle visual
    var npSec   = qs('#nowplaying-section');
    var idleSec = qs('#idle-section');
    if (npSec)   npSec.classList.toggle('hidden', !hasTrack);
    if (idleSec) idleSec.classList.toggle('hidden',  !!hasTrack);

    if (hasTrack) {
      var tEl = qs('#np-title');
      var aEl = qs('#np-artist');
      if (tEl) tEl.textContent = s.title  || '—';
      if (aEl) aEl.textContent = s.artist || '';
    }

    // Route to correct screen
    if (s.slide_url) {
      renderSlide(s.slide_url);
      showScreen('slide-screen');
    } else {
      showScreen('main-screen');
    }
  }

  // ── Render slide (image or iframe, detected by URL extension) ─────────
  function renderSlide(url) {
    var img   = qs('#slide-img');
    var frame = qs('#slide-iframe');
    var isImage = /\.(jpe?g|png|gif|webp|svg)(\?|$)/i.test(url);

    if (isImage) {
      if (frame) frame.classList.add('hidden');
      if (img) {
        img.classList.remove('hidden');
        if (img.getAttribute('src') !== url) img.setAttribute('src', url);
      }
    } else {
      if (img) img.classList.add('hidden');
      if (frame) {
        frame.classList.remove('hidden');
        if (frame.getAttribute('src') !== url) frame.setAttribute('src', url);
      }
    }
  }

  // ── Polling loop ──────────────────────────────────────────────────────
  function poll() {
    fetch('/api/status')
      .then(function(r) { return r.json(); })
      .then(function(s) { applyState(s); })
      .catch(function() { /* network hiccup — keep last state */ });

    var interval = ((cfg.display || {}).ui_poll_interval_seconds || 5) * 1000;
    setTimeout(poll, interval);
  }

  // ── Init ──────────────────────────────────────────────────────────────
  function init() {
    updateClock();
    setInterval(updateClock, 1000);

    fetch('/api/config')
      .then(function(r) { return r.json(); })
      .then(function(c) { applyConfig(c); poll(); })
      .catch(function()  {               poll(); });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
