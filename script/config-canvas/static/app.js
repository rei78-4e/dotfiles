/* Config Canvas — frontend engine. No dependencies. */
'use strict';

(() => {
  const NS = 'http://www.w3.org/2000/svg';
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const lerp = (a, b, t) => a + (b - a) * t;
  const now = () => performance.now();

  function mk(tag, attrs = {}, parent = null) {
    const el = document.createElementNS(NS, tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v === undefined || v === null) continue;
      el.setAttribute(k, String(v));
    }
    if (parent) parent.appendChild(el);
    return el;
  }

  function h(tag, attrs = {}, parent = null) {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v === undefined || v === null) continue;
      if (k === 'text') el.textContent = String(v);
      else if (k === 'class') el.className = String(v);
      else el.setAttribute(k, String(v));
    }
    if (parent) parent.appendChild(el);
    return el;
  }

  function clear(el) {
    while (el.firstChild) el.removeChild(el.firstChild);
  }

  function truncate(value, chars) {
    const str = String(value ?? '');
    return str.length <= chars ? str : str.slice(0, Math.max(0, chars - 1)) + '…';
  }

  function fmt(n) {
    return new Intl.NumberFormat('en-US').format(n);
  }

  function hash01(str) {
    let h = 2166136261;
    for (let i = 0; i < str.length; i++) {
      h ^= str.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    h = (h ^ (h >>> 13)) >>> 0;
    return h / 4294967296;
  }

  function pathKey(node) {
    if (!node) return '';
    if (S.view === 'files') return 'fs:' + node.path;
    return 'ct:' + (S.contentPath || '') + ':' + (node.line || 0) + ':' + String(node.label || '');
  }

  function debounce(fn, ms) {
    let t = 0;
    return (...args) => {
      clearTimeout(t);
      t = setTimeout(() => fn(...args), ms);
    };
  }

  const FOLDER_TINTS = [
    '#c97754', '#c4a15f', '#8fa36c', '#6f9b91', '#7d92b8', '#a582ad',
    '#b77c8a', '#a08a6b', '#699e8a', '#c08a67', '#849bb0', '#9587b0',
    '#b48f62', '#7f9e7c', '#a7776d', '#7296a0',
  ];
  const TINT_CACHE = new Map();

  function parseHex(hex) {
    const m = String(hex).replace('#', '');
    const full = m.length === 3 ? m.split('').map(c => c + c).join('') : m;
    const n = parseInt(full, 16);
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
  }

  function toHex({ r, g, b }) {
    return '#' + [r, g, b].map(v => clamp(Math.round(v), 0, 255).toString(16).padStart(2, '0')).join('');
  }

  function blend(base, tint, amount) {
    const a = parseHex(base);
    const b = parseHex(tint);
    return toHex({
      r: lerp(a.r, b.r, amount),
      g: lerp(a.g, b.g, amount),
      b: lerp(a.b, b.b, amount),
    });
  }

  function folderKeyFor(node) {
    if (S.view !== 'files') {
      const p = S.contentPath || '';
      return p.includes('/') ? p.slice(0, p.lastIndexOf('/')) : '.';
    }
    if (node.type === 'dir') return node.path === '.' ? '.' : node.path;
    return node.path.includes('/') ? node.path.slice(0, node.path.lastIndexOf('/')) : '.';
  }

  function tintForFolder(key) {
    if (key === '.' || key === '') return '#d95b3d';
    if (TINT_CACHE.has(key)) return TINT_CACHE.get(key);
    const idx = Math.floor(hash01('tint:' + key) * FOLDER_TINTS.length) % FOLDER_TINTS.length;
    const color = FOLDER_TINTS[idx];
    TINT_CACHE.set(key, color);
    return color;
  }

  function tintForNode(node) {
    return tintForFolder(folderKeyFor(node));
  }

  function timeAgo(ts) {
    if (!ts) return '';
    const seconds = Math.max(0, Date.now() / 1000 - ts);
    if (seconds < 90) return 'now';
    if (seconds < 3600) return Math.round(seconds / 60) + 'm ago';
    if (seconds < 86400) return Math.round(seconds / 3600) + 'h ago';
    if (seconds < 86400 * 30) return Math.round(seconds / 86400) + 'd ago';
    if (seconds < 86400 * 365) return Math.round(seconds / (86400 * 30)) + 'mo ago';
    return Math.round(seconds / (86400 * 365)) + 'y ago';
  }

  function nodeTag(n) {
    if (S.view !== 'files') {
      const k = String(n.kind || 'node').toUpperCase();
      return k.length > 7 ? k.slice(0, 7) : k;
    }
    if (n.path === '.') return 'ROOT';
    if (n.type === 'dir') return 'DIR';
    if (n.type === 'symlink') return 'LINK';
    const ext = String(n.ext || '').toUpperCase();
    if (ext) return ext.length > 5 ? ext.slice(0, 5) : ext;
    return String(n.kind || 'FILE').toUpperCase().slice(0, 5);
  }

  function nodeMeta(n) {
    if (S.view !== 'files') return String(n.detail || '');
    if (n.path === '.') {
      return `${n.descDirs ?? 0} dirs · ${n.descFiles ?? 0} files · ${n.descBytesLabel || ''}`;
    }
    if (n.type === 'dir') {
      return `${n.childCount ?? 0} entries · ${n.descBytesLabel || ''}`;
    }
    if (n.type === 'symlink') return `→ ${n.target || '?'}`;
    if (n.image && n.width && n.height) {
      return `${n.sizeLabel || ''} · ${n.width}×${n.height} · ${timeAgo(n.mtime)}`;
    }
    if (n.text) {
      const lines = Number.isFinite(n.lines) ? `${n.lines} L` : 'text';
      return `${n.sizeLabel || ''} · ${lines} · ${timeAgo(n.mtime)}`;
    }
    return `${n.sizeLabel || ''} · ${String(n.kind || '').toLowerCase()} · ${timeAgo(n.mtime)}`;
  }

  // ------------------------------------------------------------------
  // icons (16 × 16 line art)

  const ICONS = {
    dir: '<path d="M1.8 4.2h4.3l1.5 1.9h6.6v7.5H1.8z"/><path d="M1.8 7.2h12.4"/>',
    file: '<path d="M4 1.6h5.4L13 5.2v9.2H4z"/><path d="M9.4 1.6v3.7H13"/><path d="M5.7 8.2h5M5.7 10.4h5M5.7 12.6h3.4"/>',
    nix: '<path d="M8 1.4v13.2M2.4 4.6l11.2 6.8M13.6 4.6L2.4 11.4"/><path d="M8 3.4L6.6 2.3M8 3.4l1.4-1.1M8 12.6l-1.4 1.1M8 12.6l1.4 1.1M3.7 5.7L2.2 5.3M3.7 5.7l.4-1.5M12.3 10.3l1.5.4M12.3 10.3l-.4 1.5M12.3 5.7l1.5-.4M12.3 5.7l-.4 1.5M3.7 10.3l-1.5.4M3.7 10.3l.4 1.5"/>',
    code: '<path d="M5.2 3.1L2 8l3.2 4.9M10.8 3.1L14 8l-3.2 4.9"/><path d="M9.3 2.4L6.7 13.6"/>',
    config: '<path d="M5 3.2H3.2v9.6H5M11 3.2h1.8v9.6H11"/><path d="M7 6.1h2M7 8.1h2M7 10.1h2"/>',
    image: '<rect x="2" y="2.4" width="12" height="11.2"/><circle cx="5.4" cy="6" r="1.1"/><path d="M2.4 12.7l3.3-3.4 2.3 2.2 2.3-2.6 3.2 3.8"/>',
    binary: '<path d="M3.2 3.2h4v4h-4zM8.8 8.8h4v4h-4z"/><path d="M9.4 3.2h3.4v3.4H9.4M3.2 9.4h3.4V13H3.2"/>',
    archive: '<path d="M2.4 5.2h11.2v8.4H2.4z"/><path d="M1.8 2.6h12.4v2.6H1.8z"/><path d="M8 2.6v2.6M6.8 8.2h2.4v2H6.8z"/>',
    audio: '<path d="M6.2 12.2V4l6.4-1.5v8.1"/><ellipse cx="4.6" cy="12.3" rx="1.8" ry="1.3"/><ellipse cx="11" cy="10.7" rx="1.8" ry="1.3"/>',
    video: '<rect x="2" y="3.2" width="12" height="9.6"/><path d="M6.8 5.9l4 2.4-4 2.4z"/>',
    font: '<path d="M3.4 13L7.9 3h.4l4.3 10M5.2 9.4h5.4"/>',
    document: '<path d="M4 1.6h5.4L13 5.2v9.2H4z"/><path d="M9.4 1.6v3.7H13"/><path d="M5.6 8h5.6M5.6 10.2h5.6M5.6 12.4h3.8"/>',
    symlink: '<path d="M6.6 9.4a2.7 2.7 0 000-3.8l-1.4-1.4a2.7 2.7 0 00-3.8 3.8L2.8 9.4"/><path d="M9.4 6.6a2.7 2.7 0 000 3.8l1.4 1.4a2.7 2.7 0 003.8-3.8L13.2 6.6"/><path d="M5.8 10.2l4.4-4.4"/>',
    text: '<path d="M3.2 2.4h9.6v11.2H3.2z"/><path d="M5.4 5.6h5.2M5.4 8h5.2M5.4 10.4h3.4"/>',
    data: '<path d="M2.4 3.2h11.2v9.6H2.4z"/><path d="M5 6.2h6M5 8.2h6M5 10.2h3.4"/>',
    default: '<path d="M4 1.6h5.4L13 5.2v9.2H4z"/><path d="M9.4 1.6v3.7H13"/>',
  };

  function iconMarkup(kind) {
    const key = ICONS[kind] ? kind : (kind === 'document' ? 'document' : 'default');
    return ICONS[key];
  }

  // ------------------------------------------------------------------
  // state

  const S = {
    fs: null,
    view: 'files',
    scene: null,
    fileScene: null,
    pos: new Map(),
    dims: new Map(),
    nodeEls: new Map(),
    edgeEls: [],
    customEdgeEls: new Map(),
    keyToId: new Map(),
    adj: new Map(),
    selected: null,
    hovered: null,
    infoId: null,
    linkMode: false,
    linkSource: null,
    customLinks: [],
    contentPath: null,
    content: null,
    contentCollapsed: new Set(),
    cams: { files: null, content: null },
    cam: { x: 0, y: 0, k: 1 },
    drag: null,
    camAnim: null,
    search: '',
    searchHits: [],
    mini: null,
    contentLoading: 0,
    fileSelectTarget: null,
    restLengths: new Map(),
    velocities: new Map(),
    physics: null,
    infoTimer: 0,
    infoCloseTimer: 0,
    inspectorHover: false,
  };

  const els = {
    canvas: $('#canvas'),
    viewport: $('#viewport'),
    edgeLayer: $('#edgeLayer'),
    customLayer: $('#customLayer'),
    nodeLayer: $('#nodeLayer'),
    defs: $('#canvas defs'),
    search: $('#search'),
    searchCount: $('#searchCount'),
    contentbar: $('#contentbar'),
    fileSelect: $('#fileSelect'),
    contentMeta: $('#contentMeta'),
    rootPath: $('#rootPath'),
    inspector: $('#inspector'),
    inspBadge: $('#inspBadge'),
    inspTitle: $('#inspTitle'),
    inspSub: $('#inspSub'),
    inspMeta: $('#inspMeta'),
    inspActions: $('#inspActions'),
    inspPreview: $('#inspPreview'),
    inspClose: $('#inspClose'),
    toast: $('#toast'),
    loading: $('#loading'),
    loadingSub: $('#loadingSub'),
    help: $('#help'),
    live: $('#live'),
    liveText: $('#liveText'),
    minimap: $('#minimap'),
    minimapZoom: $('#minimapZoom'),
    minimapWrap: $('#minimapWrap'),
    statView: $('#statView'),
    statNodes: $('#statNodes'),
    statDetail: $('#statDetail'),
    statScan: $('#statScan'),
    hudCoords: $('#hudCoords'),
    hudZoom: $('#hudZoom'),
    hudVisible: $('#hudVisible'),
    btnLink: $('#btnLink'),
    btnFit: $('#btnFit'),
    btnArrange: $('#btnArrange'),
    btnRefresh: $('#btnRefresh'),
  };

  let clipSeq = 0;
  let toastTimer = 0;

  // ------------------------------------------------------------------
  // toast / loading / help

  function toast(message, ms = 2400) {
    els.toast.textContent = message;
    els.toast.classList.add('is-visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => els.toast.classList.remove('is-visible'), ms);
  }

  function showLoading(sub) {
    els.loading.classList.remove('is-done');
    els.loading.hidden = false;
    if (sub) els.loadingSub.textContent = sub;
  }

  function hideLoading() {
    els.loading.classList.add('is-done');
    setTimeout(() => { els.loading.hidden = true; }, 430);
  }

  function loadingError(message) {
    els.loading.classList.remove('is-done');
    els.loading.hidden = false;
    els.loadingSub.textContent = message;
    const card = $('.loading-card', els.loading);
    if (!card.querySelector('.retry-btn')) {
      const btn = h('button', { class: 'tool-btn', type: 'button', text: 'TRY AGAIN' }, card);
      btn.style.marginTop = '14px';
      btn.addEventListener('click', () => location.reload());
    }
  }

  function toggleHelp(force) {
    const show = force === undefined ? els.help.hidden : force;
    els.help.hidden = !show;
  }

  // ------------------------------------------------------------------
  // camera

  function applyCamera() {
    const { x, y, k } = S.cam;
    els.viewport.setAttribute('transform', `translate(${x} ${y}) scale(${k})`);
    const size = 28 * k;
    els.canvas.style.backgroundSize = `${size}px ${size}px`;
    els.canvas.style.backgroundPosition = `${x}px ${y}px`;
    els.hudZoom.textContent = Math.round(k * 100) + '%';
    els.minimapZoom.textContent = Math.round(k * 100) + '%';
    els.hudCoords.textContent = `${Math.round((0 - x) / k)}, ${Math.round((0 - y) / k)}`;
    updateMiniViewport();
  }

  function screenToWorld(sx, sy) {
    return { x: (sx - S.cam.x) / S.cam.k, y: (sy - S.cam.y) / S.cam.k };
  }

  function worldToScreen(wx, wy) {
    return { x: wx * S.cam.k + S.cam.x, y: wy * S.cam.k + S.cam.y };
  }

  function viewportSize() {
    return { w: els.canvas.clientWidth || window.innerWidth, h: els.canvas.clientHeight || window.innerHeight };
  }

  function getSceneBounds(padding = 0, filter = null) {
    if (!S.scene || !S.scene.nodes.length) return null;
    let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
    for (const n of S.scene.nodes) {
      if (filter && !filter(n)) continue;
      const p = S.pos.get(n.id);
      if (!p) continue;
      minX = Math.min(minX, p.x);
      minY = Math.min(minY, p.y);
      maxX = Math.max(maxX, p.x + p.w);
      maxY = Math.max(maxY, p.y + p.h);
    }
    if (!Number.isFinite(minX)) return null;
    return {
      minX: minX - padding,
      minY: minY - padding,
      maxX: maxX + padding,
      maxY: maxY + padding,
      w: maxX - minX + padding * 2,
      h: maxY - minY + padding * 2,
    };
  }

  function fitView(opts = {}) {
    const maxDepth = Number.isFinite(opts.maxDepth) ? opts.maxDepth : null;
    const bounds = getSceneBounds(40, maxDepth == null ? null : (n) => (n.depth ?? 0) <= maxDepth);
    if (!bounds) return;
    const { w: vw, h: vh } = viewportSize();
    const inspectorPad = document.body.classList.contains('inspector-open') ? 340 : 0;
    const topPad = S.view === 'content' ? 132 : 96;
    const padX = 72 + inspectorPad;
    const availW = Math.max(240, vw - padX - 52);
    const availH = Math.max(240, vh - topPad - 70);
    let k = Math.min(availW / bounds.w, availH / bounds.h);
    k = clamp(k, 0.08, 1.45);
    const tx = 52 + (availW - bounds.w * k) / 2 - bounds.minX * k;
    const ty = topPad + (availH - bounds.h * k) / 2 - bounds.minY * k;
    const target = { x: tx, y: ty, k };
    if (opts.animate === false) {
      S.cam = target;
      applyCamera();
    } else {
      animateCamera(target, opts.ms || 340);
    }
  }

  function animateCamera(target, ms = 320) {
    if (S.camAnim) cancelAnimationFrame(S.camAnim.raf);
    const from = { ...S.cam };
    const started = now();
    const step = () => {
      const t = clamp((now() - started) / ms, 0, 1);
      const e = 1 - Math.pow(1 - t, 3);
      S.cam = {
        x: lerp(from.x, target.x, e),
        y: lerp(from.y, target.y, e),
        k: lerp(from.k, target.k, e),
      };
      applyCamera();
      if (t < 1) S.camAnim = { raf: requestAnimationFrame(step) };
      else S.camAnim = null;
    };
    S.camAnim = { raf: requestAnimationFrame(step) };
  }

  function centerOn(id, zoom) {
    const p = S.pos.get(id);
    if (!p) return;
    const { w: vw, h: vh } = viewportSize();
    const inspectorPad = document.body.classList.contains('inspector-open') ? 345 : 0;
    const k = zoom || clamp(S.cam.k, 0.35, 1.5);
    const top = S.view === 'content' ? 110 : 70;
    const cx = 50 + (vw - inspectorPad - 100) / 2;
    const cy = top + (vh - top - 34) / 2;
    animateCamera({
      x: cx - (p.x + p.w / 2) * k,
      y: cy - (p.y + p.h / 2) * k,
      k,
    }, 320);
  }

  function zoomAt(sx, sy, factor) {
    const before = screenToWorld(sx, sy);
    const k = clamp(S.cam.k * factor, 0.09, 4.5);
    S.cam.k = k;
    S.cam.x = sx - before.x * k;
    S.cam.y = sy - before.y * k;
    applyCamera();
    scheduleMini();
  }

  // ------------------------------------------------------------------
  // scene construction: filesystem

  function fileDims(n) {
    const name = String(n.name || n.path || '');
    const isRoot = n.path === '.' || n.id === S.fs?.nodes?.[0]?.id;
    let w;
    if (n.kind === 'image') {
      w = 192;
    } else if (n.type === 'dir') {
      w = clamp(38 + Math.min(name.length, 30) * 7.0 + 58, 210, 350);
    } else {
      w = clamp(38 + Math.min(name.length, 33) * 7.0 + 34, 176, 350);
    }
    let height = 48;
    if (n.type === 'dir') height = 60;
    if (n.kind === 'image') height = 132;
    if (isRoot) { height = 64; w = Math.max(w, 296); }
    return { w: Math.round(w), h: height };
  }

  function buildFileTree(flat) {
    const byId = new Map(flat.map(n => [n.id, n]));
    const children = new Map();
    for (const n of flat) {
      if (n.parent && byId.has(n.parent)) {
        if (!children.has(n.parent)) children.set(n.parent, []);
        children.get(n.parent).push(n);
      }
    }
    for (const list of children.values()) {
      list.sort((a, b) => {
        const ad = a.type === 'dir' ? 0 : 1;
        const bd = b.type === 'dir' ? 0 : 1;
        return ad - bd || String(a.name).localeCompare(String(b.name), undefined, { numeric: true });
      });
    }
    return { byId, children };
  }

  function mulberry32(seed) {
    let a = seed >>> 0;
    return () => {
      a |= 0;
      a = (a + 0x6D2B79F5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function shuffleInPlace(list, rng) {
    for (let i = list.length - 1; i > 0; i--) {
      const j = Math.floor(rng() * (i + 1));
      [list[i], list[j]] = [list[j], list[i]];
    }
  }

  function layoutFiles() {
    const flat = S.fs.nodes;
    const { byId, children } = buildFileTree(flat);
    const rng = mulberry32((Math.random() * 0xffffffff) >>> 0);
    for (const list of children.values()) shuffleInPlace(list, rng);
    const weights = new Map();
    const weightOf = (n) => {
      if (weights.has(n.id)) return weights.get(n.id);
      const kids = children.get(n.id) || [];
      if (!kids.length) { weights.set(n.id, 1); return 1; }
      let w = 0;
      for (const kid of kids) w += kid.type === 'dir' ? Math.max(4.5, weightOf(kid)) : 1.45;
      w = Math.max(1, w);
      weights.set(n.id, w);
      return w;
    };

    const root = flat.find(n => !n.parent) || flat[0];
    const positions = new Map();
    const rootDims = fileDims(root);
    positions.set(root.id, { x: -rootDims.w / 2, y: -rootDims.h / 2, w: rootDims.w, h: rootDims.h });

    const placeChildren = (node, startAngle, endAngle, depth) => {
      const kids = children.get(node.id) || [];
      if (!kids.length) return;
      const parent = positions.get(node.id);
      if (!parent) return;
      const total = kids.reduce((sum, k) => sum + (k.type === 'dir' ? Math.max(4.5, weightOf(k)) : 1.45), 0);
      let cursor = startAngle;
      const parentCx = parent.x + parent.w / 2;
      const parentCy = parent.y + parent.h / 2;
      kids.forEach((kid, index) => {
        const weight = kid.type === 'dir' ? Math.max(4.5, weightOf(kid)) : 1.45;
        const span = (endAngle - startAngle) * (weight / total);
        const angle = cursor + span / 2;
        cursor += span;
        const dims = fileDims(kid);
        const wobble = (rng() - 0.5) * 0.46;
        let distance;
        if (kid.type === 'dir') {
          distance = 410 + Math.min(210, depth * 24) + (rng() - 0.5) * 220;
        } else {
          const rings = 2 + Math.min(3, Math.floor(((children.get(node.id) || []).length) / 11));
          const ring = Math.floor(rng() * rings);
          distance = 145 + ring * 128 + (rng() - 0.5) * 92;
          if (depth === 1) distance += 34;
        }
        const a = angle + wobble * (span / Math.max(total * 0.7, 1));
        const x = parentCx + Math.cos(a) * distance - dims.w / 2;
        const y = parentCy + Math.sin(a) * distance - dims.h / 2;
        positions.set(kid.id, { x, y, w: dims.w, h: dims.h });
        if (kid.type === 'dir') {
          const spread = Math.max(span * 0.88, Math.min(Math.PI * 1.72, 0.22 + weightOf(kid) * 0.016));
          placeChildren(kid, a - spread / 2, a + spread / 2, depth + 1);
        }
      });
    };

    const startAngle = rng() * Math.PI * 2;
    placeChildren(root, startAngle, startAngle + Math.PI * 2, 1);

    // Pull the initial constellation apart with a small deterministic
    // force simulation. No library, no layout dependency.
    const nodes = flat.map(n => {
      const p = positions.get(n.id);
      return {
        id: n.id,
        x: p.x,
        y: p.y,
        w: p.w,
        h: p.h,
        vx: (rng() - 0.5) * 4,
        vy: (rng() - 0.5) * 4,
        fixed: n.id === root.id,
        dir: n.type === 'dir',
      };
    });
    const simById = new Map(nodes.map(n => [n.id, n]));
    const edges = flat.filter(n => n.parent).map(n => {
      const a = simById.get(n.parent);
      const b = simById.get(n.id);
      return { a, b, dir: n.type === 'dir' };
    }).filter(e => e.a && e.b);

    const iterations = nodes.length > 500 ? 190 : 300;
    for (let tick = 0; tick < iterations; tick++) {
      const alpha = 1 - tick / iterations;
      for (const e of edges) {
        const { a, b } = e;
        if (!a || !b) continue;
        let dx = b.x - a.x;
        let dy = b.y - a.y;
        let dist = Math.hypot(dx, dy) || 1;
        const target = e.dir ? 430 : 195;
        const force = clamp((dist - target) * 0.0125 * alpha, -5.5, 5.5);
        dx /= dist;
        dy /= dist;
        if (!a.fixed) { a.vx += dx * force; a.vy += dy * force; }
        if (!b.fixed) { b.vx -= dx * force; b.vy -= dy * force; }
      }
      for (let i = 0; i < nodes.length; i++) {
        const a = nodes[i];
        for (let j = i + 1; j < nodes.length; j++) {
          const b = nodes[j];
          let dx = b.x - a.x;
          let dy = b.y - a.y;
          let dist2 = dx * dx + dy * dy;
          if (dist2 > 560 * 560) continue;
          let dist = Math.sqrt(dist2) || 0.001;
          const rep = (6200 * alpha) / Math.max(dist2, 2200);
          if (!a.fixed) { a.vx -= (dx / dist) * rep; a.vy -= (dy / dist) * rep; }
          if (!b.fixed) { b.vx += (dx / dist) * rep; b.vy += (dy / dist) * rep; }

          const gap = 15;
          const overlapX = (a.w + b.w) / 2 + gap - Math.abs(dx);
          const overlapY = (a.h + b.h) / 2 + gap - Math.abs(dy);
          if (overlapX > 0 && overlapY > 0) {
            const signX = dx >= 0 ? 1 : -1;
            const signY = dy >= 0 ? 1 : -1;
            const push = (overlapX < overlapY ? overlapX : overlapY) * 0.48 * alpha;
            if (overlapX < overlapY) {
              if (!a.fixed) a.x -= signX * push;
              if (!b.fixed) b.x += signX * push;
            } else {
              if (!a.fixed) a.y -= signY * push;
              if (!b.fixed) b.y += signY * push;
            }
          }
        }
      }
      for (const n of nodes) {
        if (n.fixed) { n.vx = 0; n.vy = 0; continue; }
        n.vx *= 0.76;
        n.vy *= 0.76;
        const step = Math.hypot(n.vx, n.vy);
        if (step > 19) { n.vx = (n.vx / step) * 19; n.vy = (n.vy / step) * 19; }
        n.x += n.vx;
        n.y += n.vy;
      }
    }

    S.pos = new Map();
    for (const n of nodes) {
      S.pos.set(n.id, { x: Math.round(n.x * 10) / 10, y: Math.round(n.y * 10) / 10, w: n.w, h: n.h });
    }
    const newRoot = S.pos.get(root.id);
    if (newRoot) newRoot.x = Math.round(-newRoot.w / 2);
    return { nodes: flat, edges: flat.filter(n => n.parent).map(n => ({ id: 'fe' + n.id, source: n.parent, target: n.id, kind: 'tree' })), rootId: root.id };
  }

  // ------------------------------------------------------------------
  // scene construction: content structure

  function countTree(node) {
    if (node._count !== undefined) return node._count;
    let count = 1;
    for (const c of node.children || []) count += countTree(c);
    node._count = count;
    return count;
  }

  function defaultCollapsedFor(tree) {
    const collapsed = new Set();
    countTree(tree);
    const walk = (node, depth) => {
      const kids = node.children || [];
      if (!kids.length) return;
      const huge = (node._count || 0) > 120 && depth >= 2;
      if ((depth >= 4) || huge) collapsed.add(node.id);
      if (!collapsed.has(node.id)) for (const c of kids) walk(c, depth + 1);
    };
    walk(tree, 0);
    return collapsed;
  }

  function buildContentScene() {
    if (!S.content) return null;
    const tree = S.content.tree;
    const nodes = [];
    const edges = [];
    const visibleChildren = new Map();
    const rootId = tree.id;
    const path = S.content.path;

    const walk = (node, parent) => {
      const copy = { ...node, path };
      delete copy.children;
      copy.children = node.children || [];
      copy._allChildren = node.children || [];
      copy._collapsed = S.contentCollapsed.has(node.id);
      copy._visibleChildren = [];
      nodes.push(copy);
      if (parent) edges.push({ id: 'ce' + node.id, source: parent.id, target: node.id, kind: 'content' });
      if (S.contentCollapsed.has(node.id)) return;
      for (const child of node.children || []) {
        copy._visibleChildren.push(child.id);
        walk(child, node);
      }
    };
    walk(tree, null);

    const byId = new Map(nodes.map(n => [n.id, n]));
    for (const n of nodes) {
      const kids = n._visibleChildren.map(id => byId.get(id)).filter(Boolean);
      n._kids = kids;
    }

    // dims
    const dims = new Map();
    for (const n of nodes) {
      const label = String(n.label || '');
      const tag = nodeTag(n);
      const tagWidth = Math.max(20, tag.length * 5.4 + 9);
      let w = clamp(38 + Math.min(label.length, 62) * 6.85 + tagWidth + 20, 190, 510);
      if (n.kind === 'root') w = clamp(38 + Math.min(label.length, 62) * 6.85 + tagWidth + 28, 220, 520);
      dims.set(n.id, { w: Math.round(w), h: n.kind === 'root' ? 52 : 44 });
    }

    // tidy tree: leaves get rows, parents centre over children
    let cursorY = 0;
    const ROW = 52;
    const placed = new Map();
    const place = (node, depth, x) => {
      const d = dims.get(node.id);
      const kids = node._kids;
      let y;
      if (!kids.length) {
        y = cursorY;
        cursorY += ROW;
      } else {
        const childYs = [];
        for (const kid of kids) {
          const kidX = x + d.w + 92;
          childYs.push(place(kid, depth + 1, kidX));
        }
        y = (childYs[0] + childYs[childYs.length - 1]) / 2;
      }
      placed.set(node.id, { x, yTop: y - d.h / 2, w: d.w, h: d.h });
      return y;
    };
    const rootCopy = byId.get(tree.id) || nodes[0];
    place(rootCopy, 0, 0);

    const minY = Math.min(...[...placed.values()].map(p => p.yTop));
    S.pos = new Map();
    for (const [id, p] of placed) {
      S.pos.set(id, { x: Math.round(p.x), y: Math.round(p.yTop - minY), w: p.w, h: p.h });
    }
    return { nodes, edges, rootId, path };
  }

  // ------------------------------------------------------------------
  // rendering

  function nodeClass(n) {
    const cls = ['node'];
    if (S.view === 'files') {
      cls.push('is-file-node');
      if (n.type === 'dir') cls.push('is-dir');
      if (n.kind === 'image') cls.push('is-image');
      if (n.kind === 'nix') cls.push('is-nix');
      if (n.path === '.') cls.push('is-root');
    } else {
      cls.push('is-content-node');
      cls.push('content-' + String(n.kind || 'node'));
      if (n.kind === 'root') cls.push('is-root');
      if (n.kind === 'binding' || n.kind === 'import') cls.push('is-nix');
    }
    return cls.join(' ');
  }

  function renderScene() {
    stopPhysics();
    closeInspector();
    clear(els.nodeLayer);
    clear(els.edgeLayer);
    clear(els.customLayer);
    els.defs.querySelectorAll('clipPath').forEach(c => c.remove());
    S.nodeEls.clear();
    S.edgeEls = [];
    S.customEdgeEls.clear();
    S.keyToId.clear();
    S.adj = new Map();
    S.infoId = null;
    S.hovered = null;

    if (!S.scene) return;
    const byId = new Map(S.scene.nodes.map(n => [n.id, n]));

    for (const e of S.scene.edges) {
      const a = byId.get(e.source);
      const b = byId.get(e.target);
      if (!a || !b) continue;
      const path = mk('path', { class: 'edge', d: '' }, els.edgeLayer);
      // Edge colour comes from the folder that owns the child node.
      path.style.setProperty('--edge-tint', blend('#3e3f39', tintForNode(b), 0.42));
      const item = { edge: e, path, a, b };
      S.edgeEls.push(item);
      addAdjacency(e.source, e.target);
    }

    for (const n of S.scene.nodes) {
      const p = S.pos.get(n.id);
      if (!p) continue;
      const g = createNodeEl(n, p);
      S.nodeEls.set(n.id, g);
      S.keyToId.set(pathKey(n), n.id);
    }

    updateAllEdges();
    renderCustomEdges();
    applySearchClasses();
    preparePhysics();
    updateMini();
    updateStats();
    updateHudVisible();
  }

  function addAdjacency(a, b) {
    if (!S.adj.has(a)) S.adj.set(a, new Set());
    if (!S.adj.has(b)) S.adj.set(b, new Set());
    S.adj.get(a).add(b);
    S.adj.get(b).add(a);
  }

  function createNodeEl(n, p) {
    const g = mk('g', {
      class: nodeClass(n),
      'data-id': n.id,
      transform: `translate(${p.x} ${p.y})`,
      tabindex: '0',
      role: 'button',
    }, els.nodeLayer);

    const isFile = S.view === 'files';
    const w = p.w;
    const height = p.h;
    const name = isFile ? (n.name || n.path) : (n.label || '');
    const meta = nodeMeta(n);
    const kind = isFile ? (n.kind === 'dir' ? 'dir' : n.kind) : contentIconKind(n);
    const isRoot = isFile ? n.path === '.' : n.kind === 'root';
    const tint = tintForNode(n);
    const tintAmount = isRoot ? 0 : (n.kind === 'image' ? 0.10 : (n.type === 'dir' ? 0.15 : (n.kind === 'nix' ? 0.13 : 0.09)));
    const tag = nodeTag(n);

    g.style.setProperty('--tint', tint);
    g.style.setProperty('--tint-bg', blend('#17181a', tint, tintAmount));
    g.style.setProperty('--tint-bg-dir', blend('#17181a', tint, Math.max(0.12, tintAmount + 0.03)));
    g.style.setProperty('--tint-bg-nix', blend('#17181a', tint, Math.max(0.11, tintAmount)));
    g.style.setProperty('--tint-bg-hi', blend('#202124', tint, 0.22));
    g.style.setProperty('--tint-ink', blend('#c6c0b4', tint, 0.52));

    mk('rect', { class: 'node-bg', x: 0, y: 0, width: w, height: height, rx: 1 }, g);
    mk('rect', { class: 'node-accent', x: 0, y: isRoot ? 0 : 6, width: isRoot ? 3 : 2.5, height: isRoot ? height : height - 12 }, g);
    mk('rect', { class: 'node-halo', x: -3.5, y: -3.5, width: w + 7, height: height + 7, rx: 3 }, g);

    const iconY = (isFile && n.kind === 'image') ? 8 : Math.round((height - 16) / 2);
    const icon = mk('g', {
      class: 'node-icon',
      transform: `translate(12 ${iconY})`,
    }, g);
    icon.innerHTML = iconMarkup(kind);

    const textX = isFile ? 38 : 34;
    const tagWidth = Math.max(20, tag.length * 5.4 + 9);
    const topTag = !isFile;
    const titleChars = Math.max(6, Math.floor((w - textX - (topTag ? tagWidth + 12 : 14)) / 7.05));
    const titleY = isFile
      ? (n.kind === 'image' ? 18 : (n.type === 'dir' ? 23 : (isRoot ? 25 : 20)))
      : 18;
    const title = mk('text', { class: 'node-name', x: textX, y: titleY }, g);
    title.textContent = truncate(name, titleChars);

    const metaY = isFile
      ? (n.kind === 'image' ? 35 : (n.type === 'dir' ? 42 : (isRoot ? 44 : 36)))
      : 33;
    const detail = mk('text', {
      class: isFile ? 'node-meta' : 'node-detail',
      x: textX,
      y: metaY,
    }, g);
    const detailChars = Math.max(7, Math.floor((w - textX - (topTag ? 20 : tagWidth) - 12) / 6.55));
    detail.textContent = truncate(meta, detailChars);

    const tagEl = mk('text', {
      class: 'node-tag',
      x: w - 9,
      y: topTag ? 17 : metaY,
      'text-anchor': 'end',
    }, g);
    tagEl.textContent = tag;

    if (isFile && n.kind === 'image') {
      const frameY = 44;
      const frameH = height - 53;
      mk('rect', {
        class: 'node-thumb-frame',
        x: 9, y: frameY, width: w - 18, height: frameH, rx: 1,
      }, g);
      const clipId = `clip-${n.id}-${++clipSeq}`;
      const clip = mk('clipPath', { id: clipId }, els.defs);
      mk('rect', { x: 9, y: frameY, width: w - 18, height: frameH, rx: 1 }, clip);
      const img = mk('image', {
        class: 'node-thumb',
        x: 9, y: frameY, width: w - 18, height: frameH,
        preserveAspectRatio: 'xMidYMid slice',
        'clip-path': `url(#${clipId})`,
        href: '/api/raw?path=' + encodeURIComponent(n.path),
      }, g);
      img.addEventListener('error', () => {
        img.remove();
        mk('text', {
          class: 'node-thumb-missing',
          x: w / 2, y: frameY + frameH / 2 + 3,
        }, g).textContent = 'preview unavailable';
      });
    }

    if (!isFile && (n._allChildren?.length || 0) > 0) {
      const count = countTreeChildren(n);
      const fold = mk('g', {
        class: 'fold-badge',
        transform: `translate(${w - 15} ${height - 14})`,
      }, g);
      mk('circle', { class: 'fold-bg', cx: 0, cy: 0, r: 7 }, fold);
      mk('text', { class: 'fold-text', x: 0, y: 3.1 }, fold).textContent = n._collapsed ? '+' : '−';
      fold.addEventListener('pointerdown', (e) => e.stopPropagation());
      fold.addEventListener('click', (e) => {
        e.stopPropagation();
        e.preventDefault();
        toggleFold(n.id);
      });
      const titleEl = mk('title', {}, g);
      titleEl.textContent = `${name}${count ? ' · ' + count + ' nodes' : ''}\n${meta}`;
    } else {
      const titleEl = mk('title', {}, g);
      titleEl.textContent = isFile
        ? `${n.path}\n${meta}${n.lines ? '\n' + n.lines + ' lines · ' + (n.words || 0) + ' words' : ''}`
        : `${name}\n${meta}`;
    }

    g.addEventListener('pointerenter', () => enterNode(n.id));
    g.addEventListener('pointerleave', () => leaveNode(n.id));
    g.addEventListener('focus', () => enterNode(n.id));
    g.addEventListener('blur', () => leaveNode(n.id));
    return g;
  }

  function countTreeChildren(node) {
    let count = 0;
    const walk = (n) => {
      for (const c of n.children || []) { count++; walk(c); }
    };
    walk(node);
    return count;
  }

  function contentIconKind(n) {
    const kind = String(n.kind || '');
    if (kind === 'root') return 'nix';
    if (kind === 'attrset') return 'config';
    if (kind === 'binding') return 'config';
    if (kind === 'lambda') return 'code';
    if (kind === 'import') return 'symlink';
    if (kind === 'string') return 'text';
    if (kind === 'list') return 'data';
    if (kind === 'path') return 'symlink';
    if (kind === 'call') return 'code';
    if (kind === 'table') return 'data';
    if (kind === 'heading') return 'text';
    return 'file';
  }

  function contentKindColor(kind) {
    if (kind === 'binding' || kind === 'import') return '#d2472b';
    if (kind === 'attrset' || kind === 'table') return '#1b1a17';
    if (kind === 'lambda' || kind === 'call') return '#6d665a';
    if (kind === 'string' || kind === 'literal') return '#a39b8d';
    return '#b3aa9a';
  }

  // ------------------------------------------------------------------
  // edges

  function rectExit(cx, cy, w, height, dx, dy) {
    if (dx === 0 && dy === 0) return { x: cx, y: cy };
    const tx = dx === 0 ? Infinity : (w / 2) / Math.abs(dx);
    const ty = dy === 0 ? Infinity : (height / 2) / Math.abs(dy);
    const t = Math.min(tx, ty);
    return { x: cx + dx * t, y: cy + dy * t };
  }

  function edgePath(a, b, seed = 0) {
    const pa = S.pos.get(a.id);
    const pb = S.pos.get(b.id);
    if (!pa || !pb) return '';
    const acx = pa.x + pa.w / 2;
    const acy = pa.y + pa.h / 2;
    const bcx = pb.x + pb.w / 2;
    const bcy = pb.y + pb.h / 2;
    let dx = bcx - acx;
    let dy = bcy - acy;
    let dist = Math.hypot(dx, dy) || 1;
    const nx = -dy / dist;
    const ny = dx / dist;
    const p1 = rectExit(acx, acy, pa.w, pa.h, dx, dy);
    const p2 = rectExit(bcx, bcy, pb.w, pb.h, -dx, -dy);
    dx = p2.x - p1.x;
    dy = p2.y - p1.y;
    dist = Math.hypot(dx, dy) || 1;
    const bow = (hash01(String(a.id) + '>' + String(b.id) + ':' + seed) - 0.5) * Math.min(84, dist * 0.21);
    const c1x = p1.x + dx * 0.34 + nx * bow;
    const c1y = p1.y + dy * 0.34 + ny * bow;
    const c2x = p2.x - dx * 0.34 + nx * bow;
    const c2y = p2.y - dy * 0.34 + ny * bow;
    return `M ${p1.x.toFixed(2)} ${p1.y.toFixed(2)} C ${c1x.toFixed(2)} ${c1y.toFixed(2)} ${c2x.toFixed(2)} ${c2y.toFixed(2)} ${p2.x.toFixed(2)} ${p2.y.toFixed(2)}`;
  }

  function updateAllEdges() {
    for (const item of S.edgeEls) {
      item.path.setAttribute('d', edgePath(item.a, item.b, 0));
    }
    updateCustomEdgePaths();
  }

  function updateEdgesFor(id) {
    for (const item of S.edgeEls) {
      if (item.a.id === id || item.b.id === id) {
        item.path.setAttribute('d', edgePath(item.a, item.b, 0));
      }
    }
    updateCustomEdgePaths();
  }

  function updateCustomEdgePaths() {
    for (const [key, item] of S.customEdgeEls) {
      item.path.setAttribute('d', edgePath(item.a, item.b, 7));
    }
  }

  function resolveCustomLinks() {
    const raw = loadLinks();
    const resolved = [];
    for (const link of raw) {
      const a = S.keyToId.get(link.a);
      const b = S.keyToId.get(link.b);
      if (a && b && a !== b) resolved.push({ a, b, keyA: link.a, keyB: link.b });
    }
    return resolved;
  }

  function renderCustomEdges() {
    clear(els.customLayer);
    S.customEdgeEls.clear();
    const links = resolveCustomLinks();
    for (const link of links) {
      const aNode = S.scene.nodes.find(n => n.id === link.a);
      const bNode = S.scene.nodes.find(n => n.id === link.b);
      if (!aNode || !bNode) continue;
      const path = mk('path', {
        class: 'custom-edge',
        d: '',
        'marker-end': 'url(#arrow)',
        'data-key': link.keyA + '|' + link.keyB,
      }, els.customLayer);
      path.addEventListener('contextmenu', (e) => {
        e.preventDefault();
        removeLink(link.keyA, link.keyB);
      });
      const title = mk('title', {}, path);
      title.textContent = 'freeform link · right-click to remove';
      S.customEdgeEls.set(link.keyA + '|' + link.keyB, { a: aNode, b: bNode, path });
      addAdjacency(link.a, link.b);
    }
    updateCustomEdgePaths();
  }

  // ------------------------------------------------------------------
  // spring physics: lines tug their neighbours when a node is pulled

  function preparePhysics() {
    S.restLengths = new Map();
    S.velocities = new Map();
    if (!S.scene) return;
    for (const e of S.scene.edges) {
      const a = S.pos.get(e.source);
      const b = S.pos.get(e.target);
      if (!a || !b) continue;
      const ax = a.x + a.w / 2;
      const ay = a.y + a.h / 2;
      const bx = b.x + b.w / 2;
      const by = b.y + b.h / 2;
      S.restLengths.set(e.id, Math.hypot(bx - ax, by - ay));
    }
    for (const n of S.scene.nodes) S.velocities.set(n.id, { x: 0, y: 0 });
  }

  function stopPhysics() {
    if (S.physics?.raf) cancelAnimationFrame(S.physics.raf);
    S.physics = null;
  }

  function startPhysics(pinnedId) {
    preparePhysics();
    stopPhysics();
    // Spring motion stays local: the grabbed node, its direct lines, and
    // their immediate surroundings. The rest of the atlas stays put.
    const near = new Set();
    let frontier = [pinnedId];
    near.add(pinnedId);
    for (let hop = 0; hop < 2; hop++) {
      const next = [];
      for (const id of frontier) {
        for (const other of S.adj.get(id) || []) {
          if (near.has(other)) continue;
          near.add(other);
          next.push(other);
        }
      }
      frontier = next;
    }
    const anchors = new Map();
    for (const id of near) {
      const p = S.pos.get(id);
      if (p) anchors.set(id, { x: p.x, y: p.y });
    }
    S.physics = {
      raf: 0,
      last: performance.now(),
      settleUntil: 0,
      releaseAt: 0,
      pinned: pinnedId,
      near,
      anchors,
    };
    const tick = (ts) => {
      if (!S.physics) return;
      const dt = clamp((ts - S.physics.last) / 16.667, 0.25, 2.5);
      S.physics.last = ts;
      if (!S.drag && S.physics.releaseAt && ts > S.physics.releaseAt) {
        S.physics.pinned = null;
        S.physics.releaseAt = 0;
      }
      const speed = physicsStep(dt);
      applyNodePositions();
      const settle = S.physics.settleUntil;
      if (S.drag || ts < settle || speed > 0.35) {
        S.physics.raf = requestAnimationFrame(tick);
      } else {
        S.physics = null;
        updateMini();
        updateMiniViewport();
      }
    };
    S.physics.raf = requestAnimationFrame(tick);
  }

  function releasePhysics() {
    if (!S.physics) return;
    const pinned = S.physics.pinned;
    if (pinned) {
      for (const e of S.scene?.edges || []) {
        if (e.source !== pinned && e.target !== pinned) continue;
        const a = S.pos.get(e.source);
        const b = S.pos.get(e.target);
        if (!a || !b) continue;
        S.restLengths.set(e.id, Math.hypot(
          (b.x + b.w / 2) - (a.x + a.w / 2),
          (b.y + b.h / 2) - (a.y + a.h / 2),
        ));
      }
    }
    S.physics.anchors?.delete(pinned);
    for (const v of S.velocities.values()) { v.x = 0; v.y = 0; }
    S.physics.settleUntil = performance.now() + 650;
    S.physics.releaseAt = performance.now() + 450;
  }

  function physicsStep(dt) {
    if (!S.scene) return 0;
    const pinned = S.physics?.pinned || null;
    const near = S.physics?.near || new Set(pinned ? [pinned] : []);
    const rootId = S.scene.rootId;
    for (const n of S.scene.nodes) {
      if (!S.velocities.has(n.id)) S.velocities.set(n.id, { x: 0, y: 0 });
    }

    for (const e of S.scene.edges) {
      if (!near.has(e.source) || !near.has(e.target)) continue;
      const a = S.pos.get(e.source);
      const b = S.pos.get(e.target);
      if (!a || !b) continue;
      const acx = a.x + a.w / 2;
      const acy = a.y + a.h / 2;
      const bcx = b.x + b.w / 2;
      const bcy = b.y + b.h / 2;
      const dx = bcx - acx;
      const dy = bcy - acy;
      const dist = Math.hypot(dx, dy) || 0.001;
      const rest = S.restLengths.get(e.id) ?? dist;
      const delta = clamp(dist - rest, -150, 150);
      const stiffness = (e.source === pinned || e.target === pinned) ? 0.045 : 0.018;
      const mag = delta * stiffness * dt;
      const fx = (dx / dist) * mag;
      const fy = (dy / dist) * mag;
      const va = S.velocities.get(e.source);
      const vb = S.velocities.get(e.target);
      if (!va || !vb) continue;
      if (e.source === pinned) {
        vb.x -= fx;
        vb.y -= fy;
      } else if (e.target === pinned) {
        va.x += fx;
        va.y += fy;
      } else {
        va.x += fx * 0.5;
        va.y += fy * 0.5;
        vb.x -= fx * 0.5;
        vb.y -= fy * 0.5;
      }
    }

    let totalSpeed = 0;
    for (const n of S.scene.nodes) {
      const p = S.pos.get(n.id);
      const v = S.velocities.get(n.id);
      if (!p || !v) continue;
      if (n.id === pinned) {
        v.x = 0;
        v.y = 0;
        continue;
      }
      const anchored = n.id === rootId || !near.has(n.id);
      if (anchored) {
        v.x = 0;
        v.y = 0;
        continue;
      }
      v.x *= 0.82;
      v.y *= 0.82;
      const anchor = S.physics?.anchors?.get(n.id);
      if (anchor) {
        v.x += (anchor.x - p.x) * 0.0055 * dt;
        v.y += (anchor.y - p.y) * 0.0055 * dt;
      }
      const step = Math.hypot(v.x, v.y);
      if (step > 10) {
        v.x = (v.x / step) * 10;
        v.y = (v.y / step) * 10;
      }
      p.x += v.x * dt;
      p.y += v.y * dt;
      totalSpeed += Math.abs(v.x) + Math.abs(v.y);
    }

    // Flat collision so the constellation does not fold into itself.
    const nodes = S.scene.nodes;
    for (let i = 0; i < nodes.length; i++) {
      const a = S.pos.get(nodes[i].id);
      if (!a) continue;
      for (let j = i + 1; j < nodes.length; j++) {
        const b = S.pos.get(nodes[j].id);
        if (!b) continue;
        const dx = (b.x + b.w / 2) - (a.x + a.w / 2);
        const dy = (b.y + b.h / 2) - (a.y + a.h / 2);
        if (Math.abs(dx) > 700 || Math.abs(dy) > 500) continue;
        const gap = 10;
        const ox = (a.w + b.w) / 2 + gap - Math.abs(dx);
        const oy = (a.h + b.h) / 2 + gap - Math.abs(dy);
        if (ox <= 0 || oy <= 0) continue;
        const aIn = near.has(nodes[i].id);
        const bIn = near.has(nodes[j].id);
        // Collisions only resolve inside the local spring cluster. A node
        // dropped over the static atlas is allowed to overlap it.
        if (!aIn || !bIn) continue;
        const aFixed = nodes[i].id === pinned || nodes[i].id === rootId;
        const bFixed = nodes[j].id === pinned || nodes[j].id === rootId;
        if (aFixed && bFixed) continue;
        const signX = dx >= 0 ? 1 : -1;
        const signY = dy >= 0 ? 1 : -1;
        const push = (ox < oy ? ox : oy) * 0.34 * dt;
        if (ox < oy) {
          if (aFixed) b.x += signX * push;
          else if (bFixed) a.x -= signX * push;
          else { a.x -= signX * push; b.x += signX * push; }
        } else {
          if (aFixed) b.y += signY * push;
          else if (bFixed) a.y -= signY * push;
          else { a.y -= signY * push; b.y += signY * push; }
        }
      }
    }
    return totalSpeed;
  }

  function applyNodePositions() {
    for (const [id, p] of S.pos) {
      const el = S.nodeEls.get(id);
      if (el) el.setAttribute('transform', `translate(${p.x} ${p.y})`);
    }
    updateAllEdges();
    scheduleMini();
  }

  // ------------------------------------------------------------------
  // hover highlight

  function hoverNode(id) {
    if (S.hovered === id) return;
    S.hovered = id;
    if (!id) {
      for (const el of S.nodeEls.values()) {
        el.classList.remove('is-hot', 'is-near', 'is-dim');
      }
      for (const item of S.edgeEls) item.path.classList.remove('is-hot', 'is-near', 'is-dim');
      for (const item of S.customEdgeEls.values()) item.path.classList.remove('is-hot', 'is-dim');
      return;
    }
    const near = S.adj.get(id) || new Set();
    for (const [nid, el] of S.nodeEls) {
      el.classList.toggle('is-hot', nid === id);
      el.classList.toggle('is-near', nid !== id && near.has(nid));
      el.classList.toggle('is-dim', nid !== id && !near.has(nid));
    }
    for (const item of S.edgeEls) {
      const hot = item.a.id === id || item.b.id === id;
      item.path.classList.toggle('is-hot', hot);
      item.path.classList.toggle('is-dim', !hot);
      if (!hot) item.path.classList.remove('is-near');
    }
    for (const item of S.customEdgeEls.values()) {
      const hot = item.a.id === id || item.b.id === id;
      item.path.classList.toggle('is-hot', hot);
      item.path.classList.toggle('is-dim', !hot);
    }
  }

  // ------------------------------------------------------------------
  // hover dossier + inspector

  function findNode(id) {
    return S.scene?.nodes.find(n => n.id === id) || null;
  }

  function enterNode(id) {
    if (S.drag) return;
    hoverNode(id);
    if (S.infoCloseTimer) {
      clearTimeout(S.infoCloseTimer);
      S.infoCloseTimer = 0;
    }
    clearTimeout(S.infoTimer);
    S.infoTimer = setTimeout(() => {
      if (!S.drag && S.hovered === id) showInfoFor(id);
    }, 90);
  }

  function leaveNode(id) {
    if (S.hovered === id) hoverNode(null);
    clearTimeout(S.infoTimer);
    S.infoTimer = 0;
    if (S.infoId) scheduleInfoClose();
  }

  function scheduleInfoClose() {
    if (S.inspectorHover) return;
    clearTimeout(S.infoCloseTimer);
    S.infoCloseTimer = setTimeout(() => {
      if (!S.inspectorHover && !S.drag) closeInspector();
    }, 300);
  }

  function cancelInfoClose() {
    if (S.infoCloseTimer) {
      clearTimeout(S.infoCloseTimer);
      S.infoCloseTimer = 0;
    }
    clearTimeout(S.infoTimer);
  }

  function showInfoFor(id, opts = {}) {
    const node = findNode(id);
    if (!node) return;
    S.selected = id;
    S.infoId = id;
    openInspector(node);
    if (opts.center) centerOn(id);
  }

  function selectNode(id, opts = {}) {
    showInfoFor(id, opts);
  }

  function clearSelection() {
    S.selected = null;
    closeInspector();
  }

  function closeInspector() {
    cancelInfoClose();
    S.infoId = null;
    S.inspectorHover = false;
    els.inspector.classList.remove('is-open');
    els.inspector.setAttribute('aria-hidden', 'true');
    document.body.classList.remove('inspector-open');
  }

  function openInspector(node) {
    document.body.classList.add('inspector-open');
    els.inspector.classList.add('is-open');
    els.inspector.setAttribute('aria-hidden', 'false');
    els.inspector.scrollTop = 0;
    if (S.view === 'files') renderFileInspector(node);
    else renderContentInspector(node);
  }

  function metaRow(key, value) {
    return `<div class="k">${key}</div><div class="v">${escapeHtml(value)}</div>`;
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  function actionButton(label, handler, opts = {}) {
    const b = h('button', { class: 'tool-btn small' + (opts.accent ? ' is-active' : ''), type: 'button', text: label });
    b.addEventListener('click', handler);
    return b;
  }

  function setActions(buttons) {
    clear(els.inspActions);
    for (const b of buttons) if (b) els.inspActions.appendChild(b);
  }

  function renderFileInspector(node) {
    const isDir = node.type === 'dir';
    const isRoot = node.path === '.';
    els.inspBadge.textContent = isRoot ? 'ROOT FOLDER' : (isDir ? 'DIRECTORY' : (node.kind || 'FILE').toUpperCase());
    els.inspBadge.classList.toggle('is-accent', node.kind === 'nix');
    els.inspTitle.textContent = isRoot ? S.fs.rootName : node.name;
    els.inspSub.textContent = isRoot ? S.fs.root : node.path;
    const rows = [];
    if (isDir) {
      rows.push(metaRow('TYPE', isRoot ? 'root folder · directory' : 'directory'));
      rows.push(metaRow('ENTRIES', `${node.childCount || 0} immediate`));
      rows.push(metaRow('CONTAINS', `${node.descFiles || 0} files · ${node.descDirs || 0} folders`));
      rows.push(metaRow('TOTAL SIZE', node.descBytesLabel || '0 B'));
      if (node.modeOctal) rows.push(metaRow('MODE', `${node.modeOctal} · ${node.mode || ''}`));
      if (node.owner) rows.push(metaRow('OWNER', `${node.owner}:${node.group || '?'}`));
      if (node.modified) rows.push(metaRow('MODIFIED', node.modified));
      if (isRoot) {
        rows.push(metaRow('SKIPPED', `${S.fs.stats.skipped.length} generated folders · ${fmt(S.fs.stats.skippedFiles)} files`));
        rows.push(metaRow('LAST SCAN', `${S.fs.scanMs} ms · ${S.fs.generatedAt}`));
      }
    } else {
      rows.push(metaRow('TYPE', `${node.kind || 'file'} · ${node.mime || 'unknown'}`));
      rows.push(metaRow('SIZE', node.sizeLabel || '0 B'));
      if (node.text && !node.image) {
        const lines = Number.isFinite(node.lines) ? node.lines : '—';
        const words = Number.isFinite(node.words) ? node.words : '—';
        rows.push(metaRow('CONTENT', `${lines} lines · ${words} words`));
      }
      if (node.image && node.width) rows.push(metaRow('PIXELS', `${node.width} × ${node.height}`));
      rows.push(metaRow('EXT', node.ext || '—'));
      if (node.modified) rows.push(metaRow('MODIFIED', `${node.modified}  (${timeAgo(node.mtime)})`));
      if (node.modeOctal) rows.push(metaRow('MODE', `${node.modeOctal} · ${node.mode || ''}`));
      if (node.owner) rows.push(metaRow('OWNER', `${node.owner}:${node.group || '?'}`));
      if (node.target) rows.push(metaRow('TARGET', node.target + (node.targetSizeLabel ? ` · ${node.targetSizeLabel}` : '')));
    }
    els.inspMeta.innerHTML = rows.join('');

    const actions = [];
    actions.push(actionButton('CENTER', () => centerOn(node.id, Math.max(0.6, S.cam.k))));
    actions.push(actionButton('COPY PATH', () => copyPath(node.path)));
    if (!isDir && node.text && node.structured) {
      actions.push(actionButton('STRUCTURE', () => {
        setView('content');
        loadContent(node.path);
      }, { accent: true }));
    }
    if (!isDir && node.text && !node.image) {
      actions.push(actionButton('TEXT', () => openRaw(node.path)));
    }
    if (!isDir && node.kind === 'image') {
      actions.push(actionButton('IMAGE', () => openRaw(node.path)));
    }
    setActions(actions);

    clear(els.inspPreview);
    h('div', {
      class: 'factline',
      text: isDir
        ? `${node.descFiles || 0} files · ${node.descDirs || 0} folders · ${node.descBytesLabel || '0 B'} beneath this branch`
        : `${node.sizeLabel || '0 B'} · ${node.image ? 'image' : (node.text ? (Number.isFinite(node.lines) ? node.lines + ' lines' : 'text file') : 'binary')}${node.width ? ' · ' + node.width + '×' + node.height : ''} · ${timeAgo(node.mtime)}`,
    }, els.inspPreview);
    if (isDir) {
      const label = h('div', { class: 'preview-label', text: 'CONTAINS' }, els.inspPreview);
      const row = h('div', { class: 'chip-row' }, els.inspPreview);
      const kids = (S.fs.nodes || []).filter(n => n.parent === node.id).slice(0, 28);
      for (const kid of kids) {
        const chip = h('button', { class: 'chip', type: 'button', text: kid.name }, row);
        chip.addEventListener('click', () => {
          selectNode(kid.id);
          centerOn(kid.id);
        });
      }
      if (!kids.length) h('div', { class: 'empty', text: 'empty directory' }, els.inspPreview);
      return;
    }
    if (node.kind === 'audio' || node.kind === 'video') {
      h('div', { class: 'preview-label', text: node.kind === 'audio' ? 'AUDIO PREVIEW' : 'VIDEO PREVIEW' }, els.inspPreview);
      const media = h(node.kind === 'audio' ? 'audio' : 'video', {
        controls: 'controls',
        src: '/api/raw?path=' + encodeURIComponent(node.path),
      }, els.inspPreview);
      if (node.kind === 'video') media.setAttribute('playsinline', '');
      return;
    }
    if (node.kind === 'document') {
      h('div', { class: 'preview-label', text: 'DOCUMENT' }, els.inspPreview);
      h('a', {
        class: 'file-open',
        href: '/api/raw?path=' + encodeURIComponent(node.path),
        target: '_blank',
        rel: 'noreferrer',
        text: 'open ' + (node.ext || 'document') + ' ↗',
      }, els.inspPreview);
      return;
    }
    if (!node.text && !node.image) {
      h('div', { class: 'preview-label', text: 'BINARY PREVIEW' }, els.inspPreview);
      const pre = h('pre', { class: 'hex', text: 'reading…' }, els.inspPreview);
      fetchPreview(node.path).then(data => {
        if (S.infoId !== node.id) return;
        pre.textContent = data.hex || 'no preview';
      }).catch(() => { if (S.infoId === node.id) pre.textContent = 'preview unavailable'; });
      return;
    }
    const label = h('div', { class: 'preview-label', text: node.image ? 'PREVIEW' : 'TEXT PREVIEW' }, els.inspPreview);
    if (node.image) {
      const img = h('img', { src: '/api/raw?path=' + encodeURIComponent(node.path), alt: node.name }, els.inspPreview);
      img.addEventListener('error', () => { img.replaceWith(h('div', { class: 'empty', text: 'preview unavailable' }, els.inspPreview)); });
      const a = h('a', { class: 'file-open', href: '/api/raw?path=' + encodeURIComponent(node.path), target: '_blank', rel: 'noreferrer', text: 'open original ↗' }, els.inspPreview);
      return;
    }
    fetchPreview(node.path).then(data => {
      if (S.infoId !== node.id) return;
      if (data.text) {
        const pre = h('pre', { text: '' }, els.inspPreview);
        pre.textContent = data.text.split('\n').slice(0, 90).join('\n');
        if (data.text.split('\n').length > 90) pre.textContent += '\n…';
      } else if (data.url) {
        h('a', { class: 'file-open', href: data.url, target: '_blank', rel: 'noreferrer', text: 'open file ↗' }, els.inspPreview);
      } else {
        h('div', { class: 'empty', text: 'no preview' }, els.inspPreview);
      }
    }).catch(() => {
      if (S.infoId === node.id) h('div', { class: 'empty', text: 'preview unavailable' }, els.inspPreview);
    });
  }

  function renderContentInspector(node) {
    const total = countTreeChildren(node);
    els.inspBadge.textContent = String(node.kind || 'NODE').toUpperCase();
    els.inspBadge.classList.toggle('is-accent', node.kind === 'binding' || node.kind === 'import');
    els.inspTitle.textContent = node.label || node.kind;
    els.inspSub.textContent = `${S.contentPath}${node.line ? ' · line ' + node.line : ''}`;
    const rows = [];
    rows.push(metaRow('KIND', node.kind || 'node'));
    if (node.line) rows.push(metaRow('LINE', String(node.line)));
    if (node.detail) rows.push(metaRow('DETAIL', node.detail));
    rows.push(metaRow('SUBTREE', `${total} node${total === 1 ? '' : 's'}`));
    if (node._allChildren?.length) rows.push(metaRow('BRANCH', node._collapsed ? 'folded' : 'open'));
    els.inspMeta.innerHTML = rows.join('');
    const actions = [];
    actions.push(actionButton('CENTER', () => centerOn(node.id, Math.max(0.55, S.cam.k))));
    if ((node._allChildren || []).length) {
      actions.push(actionButton(node._collapsed ? 'EXPAND' : 'FOLD', () => toggleFold(node.id), { accent: true }));
    }
    actions.push(actionButton('FILE IN FILES', () => {
      setView('files');
      const target = (S.fs.nodes || []).find(n => n.path === S.contentPath);
      if (target) {
        selectNode(target.id);
        centerOn(target.id);
      }
    }));
    setActions(actions);

    clear(els.inspPreview);
    h('div', { class: 'preview-label', text: 'SOURCE FRAGMENT' }, els.inspPreview);
    const pre = h('pre', { text: 'reading…' }, els.inspPreview);
    fetchFragment(S.contentPath, node.line || 1).then(data => {
      if (S.infoId !== node.id) return;
      clear(pre);
      for (const line of data.lines || []) {
        const s = h('span', { class: 'src-line' + (line.n === data.line ? ' is-current' : '') }, pre);
        const num = h('span', { class: 'src-num', text: String(line.n) }, s);
        s.appendChild(document.createTextNode(' ' + line.text));
      }
      if (!data.lines || !data.lines.length) pre.textContent = 'no source';
    }).catch(() => { if (S.infoId === node.id) pre.textContent = 'source unavailable'; });
  }

  function copyPath(path) {
    const value = path;
    if (navigator.clipboard?.writeText) {
      navigator.clipboard.writeText(value).then(() => toast('PATH COPIED'), () => toast('COPY FAILED'));
    } else {
      toast('CLIPBOARD UNAVAILABLE');
    }
  }

  function openRaw(path) {
    window.open('/api/raw?path=' + encodeURIComponent(path), '_blank', 'noopener');
  }

  async function fetchPreview(path) {
    const res = await fetch('/api/preview?path=' + encodeURIComponent(path), { cache: 'no-store' });
    if (!res.ok) throw new Error('preview failed');
    return res.json();
  }

  async function fetchFragment(path, line) {
    const res = await fetch('/api/fragment?path=' + encodeURIComponent(path) + '&line=' + encodeURIComponent(line), { cache: 'no-store' });
    if (!res.ok) throw new Error('fragment failed');
    return res.json();
  }

  // ------------------------------------------------------------------
  // content parsing/load

  function populateFileSelect() {
    clear(els.fileSelect);
    const files = S.fs?.files || [];
    const nix = files.filter(f => f.ext === 'nix');
    const structured = files.filter(f => f.ext !== 'nix' && f.structured);
    const text = files.filter(f => !f.structured);
    const addGroup = (label, list) => {
      if (!list.length) return;
      const group = h('optgroup', { label });
      for (const f of list) {
        const opt = h('option', { value: f.path });
        opt.textContent = f.path
          + (f.sizeLabel ? '  ·  ' + f.sizeLabel : '')
          + (Number.isFinite(f.lines) ? '  ·  ' + f.lines + ' L' : '');
        group.appendChild(opt);
      }
      els.fileSelect.appendChild(group);
    };
    addGroup('NIX', nix);
    addGroup('STRUCTURED', structured);
    addGroup('TEXT', text);
    if (S.contentPath) els.fileSelect.value = S.contentPath;
  }

  async function loadContent(path, opts = {}) {
    if (!path) return;
    const token = ++S.contentLoading;
    S.contentPath = path;
    els.fileSelect.value = path;
    els.contentMeta.textContent = 'parsing ' + path + ' …';
    try {
      const res = await fetch('/api/content?path=' + encodeURIComponent(path), { cache: 'no-store' });
      if (!res.ok) throw new Error((await res.json().catch(() => ({}))).error || 'cannot structure file');
      const data = await res.json();
      if (token !== S.contentLoading) return;
      S.content = data;
      S.contentCollapsed = defaultCollapsedFor(data.tree);
      buildAndShowContent(opts);
      els.contentMeta.textContent = `${data.tree.stats.nodes} nodes · depth ${data.tree.stats.maxDepth} · ${data.sizeLabel} · parsed ${data.parseMs ?? 0} ms`;
    } catch (err) {
      if (token !== S.contentLoading) return;
      console.error(err);
      els.contentMeta.textContent = 'error: ' + err.message;
      toast('CONTENT ERROR · ' + err.message.toUpperCase(), 3200);
    }
  }

  function buildAndShowContent(opts = {}) {
    S.scene = buildContentScene();
    if (!S.scene) return;
    S.selected = null;
    closeInspector();
    renderScene();
    if (S.cams.content && opts.keepCamera) {
      S.cam = { ...S.cams.content };
      applyCamera();
    } else {
      fitView({ animate: false });
      S.cams.content = { ...S.cam };
    }
    updateStats();
  }

  function toggleFold(id) {
    if (S.view !== 'content' || !S.content) return;
    if (S.contentCollapsed.has(id)) S.contentCollapsed.delete(id);
    else S.contentCollapsed.add(id);
    const selected = S.selected;
    buildAndShowContent({ keepCamera: true });
    if (selected && findNode(selected)) selectNode(selected);
    else closeInspector();
    els.contentMeta.textContent = `${S.content.tree.stats.nodes} nodes · ${visibleCount()} visible · depth ${S.content.tree.stats.maxDepth}`;
  }

  function visibleCount() {
    return S.scene?.nodes.length || 0;
  }

  // ------------------------------------------------------------------
  // search

  function applySearchClasses() {
    const q = S.search.trim().toLowerCase();
    S.searchHits = [];
    if (!S.scene) return;
    if (!q) {
      for (const el of S.nodeEls.values()) el.classList.remove('is-match', 'is-search-dim');
      els.searchCount.textContent = '';
      return;
    }
    for (const n of S.scene.nodes) {
      const hay = (S.view === 'files' ? [n.name, n.path, n.ext, n.kind] : [n.label, n.detail, n.kind]).join(' ').toLowerCase();
      const hit = hay.includes(q);
      const el = S.nodeEls.get(n.id);
      if (el) {
        el.classList.toggle('is-match', hit);
        el.classList.toggle('is-search-dim', !hit);
      }
      if (hit) S.searchHits.push(n.id);
    }
    els.searchCount.textContent = S.searchHits.length ? `${S.searchHits.length} HIT${S.searchHits.length === 1 ? '' : 'S'}` : 'NONE';
  }

  function runSearch({ jump = false } = {}) {
    applySearchClasses();
    if (jump && S.searchHits.length) {
      centerOn(S.searchHits[0], Math.max(0.7, S.cam.k));
    }
  }

  // ------------------------------------------------------------------
  // stats / hud / minimap

  function updateStats() {
    els.statView.textContent = S.view === 'files' ? 'FILES' : 'CONTENT';
    if (S.view === 'files') {
      els.statNodes.textContent = `${fmt(S.fs.stats.nodes)} NODES`;
      els.statDetail.textContent = `${fmt(S.fs.stats.dirs)} DIRS · ${fmt(S.fs.stats.files)} FILES · ${fmt(S.fs.stats.textFiles || 0)} TEXT · ${fmt(S.fs.stats.imageFiles || 0)} IMG · ${S.fs.stats.bytesLabel}`;
      els.statScan.textContent = `${S.fs.scanMs} MS SCAN`;
      if (els.statScan) els.statScan.title = S.fs.generatedAt;
    } else if (S.content) {
      els.statNodes.textContent = `${fmt(visibleCount())} / ${fmt(S.content.tree.stats.nodes)} NODES`;
      els.statDetail.textContent = S.content.path;
      els.statScan.textContent = `${S.content.parseMs ?? 0} MS PARSE · DEPTH ${S.content.tree.stats.maxDepth}`;
    } else {
      els.statNodes.textContent = 'NO CONTENT';
      els.statDetail.textContent = 'choose a file';
      els.statScan.textContent = '—';
    }
    updateHudVisible();
  }

  function updateHudVisible() {
    els.hudVisible.textContent = `${fmt(visibleCount())} visible`;
  }

  let miniFrame = 0;
  function scheduleMini() {
    if (miniFrame) return;
    miniFrame = requestAnimationFrame(() => { miniFrame = 0; updateMiniViewport(); });
  }

  function updateMini() {
    const svg = els.minimap;
    clear(svg);
    if (!S.scene || !S.scene.nodes.length) { S.mini = null; return; }
    const bounds = getSceneBounds(0);
    if (!bounds) { S.mini = null; return; }
    const W = 200, H = 120, pad = 8;
    const scale = Math.min((W - pad * 2) / Math.max(bounds.w, 1), (H - pad * 2) / Math.max(bounds.h, 1));
    const ox = (W - bounds.w * scale) / 2 - bounds.minX * scale;
    const oy = (H - bounds.h * scale) / 2 - bounds.minY * scale;
    S.mini = { scale, ox, oy };
    for (const n of S.scene.nodes) {
      const p = S.pos.get(n.id);
      if (!p) continue;
      const rect = mk('rect', {
        class: 'mini-node' + (S.view === 'files' && n.type === 'dir' ? ' is-dir' : '') + (S.view === 'files' && n.kind === 'image' ? ' is-img' : ''),
        x: (p.x * scale + ox).toFixed(1),
        y: (p.y * scale + oy).toFixed(1),
        width: Math.max(1.2, p.w * scale).toFixed(1),
        height: Math.max(1.2, p.h * scale).toFixed(1),
      }, svg);
      rect.style.fill = tintForNode(n);
      rect.style.opacity = S.view === 'files' && n.type === 'dir' ? '0.8' : '0.52';
    }
    mk('rect', { class: 'mini-view', x: 0, y: 0, width: 0, height: 0 }, svg);
    updateMiniViewport();
  }

  function updateMiniViewport() {
    if (!S.mini) return;
    const rect = els.minimap.querySelector('.mini-view');
    if (!rect) return;
    const { w: vw, h: vh } = viewportSize();
    const a = screenToWorld(0, 0);
    const b = screenToWorld(vw, vh);
    const x = a.x * S.mini.scale + S.mini.ox;
    const y = a.y * S.mini.scale + S.mini.oy;
    const width = (b.x - a.x) * S.mini.scale;
    const height = (b.y - a.y) * S.mini.scale;
    rect.setAttribute('x', x.toFixed(1));
    rect.setAttribute('y', y.toFixed(1));
    rect.setAttribute('width', Math.max(2, width).toFixed(1));
    rect.setAttribute('height', Math.max(2, height).toFixed(1));
  }

  function minimapJump(ev) {
    if (!S.mini) return;
    const rect = els.minimap.getBoundingClientRect();
    const px = ((ev.clientX - rect.left) / rect.width) * 200;
    const py = ((ev.clientY - rect.top) / rect.height) * 120;
    // account for preserveAspectRatio: the rendering fills via CSS exactly to
    // the 200×120 viewBox, so the direct mapping is valid.
    const worldX = (px - S.mini.ox) / S.mini.scale;
    const worldY = (py - S.mini.oy) / S.mini.scale;
    const { w: vw, h: vh } = viewportSize();
    animateCamera({
      x: vw / 2 - worldX * S.cam.k,
      y: vh / 2 - worldY * S.cam.k,
      k: S.cam.k,
    }, 280);
    scheduleMini();
  }

  // ------------------------------------------------------------------
  // view switching

  function setView(view) {
    if (view === S.view) {
      if (view === 'content' && !S.content && S.fs) {
        const preferred = (S.fs.files || []).find(f => f.ext === 'nix' && f.path === 'flake.nix') || (S.fs.files || []).find(f => f.structured) || (S.fs.files || [])[0];
        if (preferred) loadContent(preferred.path);
      }
      return;
    }
    S.cams[S.view] = { ...S.cam };
    S.view = view;
    S.selected = null;
    S.hovered = null;
    S.linkSource = null;
    closeInspector();
    $$('.switch-btn').forEach(b => {
      const active = b.dataset.view === view;
      b.classList.toggle('is-active', active);
      b.setAttribute('aria-selected', active ? 'true' : 'false');
    });
    els.contentbar.hidden = view !== 'content';
    els.canvas.classList.toggle('is-linking', S.linkMode);
    if (view === 'files') {
      S.scene = buildFileScene();
      renderScene();
      if (S.cams.files) { S.cam = { ...S.cams.files }; applyCamera(); }
      else fitView({ animate: false });
      S.cams.files = { ...S.cam };
      updateStats();
    } else {
      if (!S.content) {
        const preferred = (S.fs?.files || []).find(f => f.ext === 'nix' && f.path === 'flake.nix') || (S.fs?.files || []).find(f => f.structured) || (S.fs?.files || [])[0];
        if (preferred) {
          loadContent(preferred.path);
        } else {
          toast('NO TEXT FILES TO STRUCTURE');
        }
        updateStats();
        return;
      }
      buildAndShowContent({ keepCamera: Boolean(S.cams.content) });
    }
  }

  function buildFileScene(opts = {}) {
    if (S.fileScene && !opts.fresh) return S.fileScene;
    const lay = layoutFiles();
    S.fileScene = { view: 'files', nodes: lay.nodes, edges: lay.edges, rootId: lay.rootId };
    return S.fileScene;
  }

  function arrangeMap() {
    if (!S.fs) return;
    if (S.view !== 'files') setView('files');
    stopPhysics();
    S.fileScene = null;
    S.scene = buildFileScene({ fresh: true });
    S.selected = null;
    S.hovered = null;
    closeInspector();
    renderScene();
    fitView({ animate: true, maxDepth: 1 });
    S.cams.files = { ...S.cam };
    toast('ARRANGED · ROOT FILES STILL ATTACHED TO THE ROOT FOLDER', 2800);
  }

  // ------------------------------------------------------------------
  // node dragging / panning / interaction

  function nodeFromEvent(ev) {
    const g = ev.target.closest?.('.node');
    return g ? g.getAttribute('data-id') : null;
  }

  function getPointer(ev) {
    const rect = els.canvas.getBoundingClientRect();
    return { x: ev.clientX - rect.left, y: ev.clientY - rect.top };
  }

  function startPan(ev) {
    const pt = getPointer(ev);
    S.camAnim && cancelAnimationFrame(S.camAnim.raf);
    S.camAnim = null;
    S.drag = {
      kind: 'pan',
      rightButton: ev.button === 2,
      sx: pt.x,
      sy: pt.y,
      camX: S.cam.x,
      camY: S.cam.y,
      moved: false,
    };
    els.canvas.classList.add('is-panning');
    els.canvas.setPointerCapture?.(ev.pointerId);
  }

  function startNodeDrag(ev, id) {
    const node = findNode(id);
    const p = S.pos.get(id);
    if (!node || !p) return;
    const pt = getPointer(ev);
    S.camAnim && cancelAnimationFrame(S.camAnim.raf);
    S.camAnim = null;
    S.drag = {
      kind: 'node',
      id,
      sx: pt.x,
      sy: pt.y,
      ox: p.x,
      oy: p.y,
      moved: false,
      originalHover: S.hovered,
    };
    S.nodeEls.get(id)?.classList.add('is-dragging');
    els.canvas.setPointerCapture?.(ev.pointerId);
  }

  function onPointerMove(ev) {
    if (!S.drag) return;
    const pt = getPointer(ev);
    const dx = pt.x - S.drag.sx;
    const dy = pt.y - S.drag.sy;
    if (!S.drag.moved && Math.hypot(dx, dy) > 3) {
      S.drag.moved = true;
      if (S.drag.kind === 'node') {
        closeInspector();
        startPhysics(S.drag.id);
      }
    }
    if (!S.drag.moved) return;
    ev.preventDefault();
    if (S.drag.kind === 'pan') {
      S.cam.x = S.drag.camX + dx;
      S.cam.y = S.drag.camY + dy;
      applyCamera();
      scheduleMini();
    } else if (S.drag.kind === 'node') {
      const p = S.pos.get(S.drag.id);
      if (!p) return;
      p.x = S.drag.ox + dx / S.cam.k;
      p.y = S.drag.oy + dy / S.cam.k;
      // The rAF spring loop applies the transform and pulls neighbours.
    }
  }

  function onPointerUp(ev) {
    if (!S.drag) return;
    const drag = S.drag;
    S.drag = null;
    els.canvas.classList.remove('is-panning');
    if (drag.kind === 'node') {
      S.nodeEls.get(drag.id)?.classList.remove('is-dragging');
      releasePhysics();
      if (drag.moved) {
        toast('SPRINGS SETTLING · THE CONSTELLATION FOLLOWED', 1800);
      } else {
        activateNode(drag.id);
      }
    } else if (!drag.moved && !drag.rightButton) {
      clearSelection();
    }
    scheduleMini();
    if (els.minimap) updateMiniViewport();
  }

  function activateNode(id) {
    const node = findNode(id);
    if (!node) return;
    if (S.linkMode) {
      toggleLinkFrom(id);
      return;
    }
    // Mouse users get the dossier on hover. Touch users get it on tap.
    if (window.matchMedia?.('(hover: none)').matches) showInfoFor(id);
  }

  // ------------------------------------------------------------------
  // freeform link mode

  function linksKey() {
    return 'config-canvas.links.v1:' + (S.fs?.root || 'root');
  }

  function loadLinks() {
    try {
      const raw = JSON.parse(localStorage.getItem(linksKey()) || '[]');
      if (!Array.isArray(raw)) return [];
      return raw.filter(x => x && typeof x.a === 'string' && typeof x.b === 'string');
    } catch {
      return [];
    }
  }

  function saveLinks(links) {
    try {
      localStorage.setItem(linksKey(), JSON.stringify(links));
    } catch { /* private mode, ignore */ }
  }

  function toggleLinkMode(force) {
    S.linkMode = force === undefined ? !S.linkMode : !!force;
    els.btnLink.classList.toggle('is-active', S.linkMode);
    els.canvas.classList.toggle('is-linking', S.linkMode);
    if (!S.linkMode) {
      S.linkSource = null;
      for (const el of S.nodeEls.values()) el.classList.remove('is-link-source', 'is-link-target');
      toast('LINK MODE OFF');
    } else {
      toast('LINK MODE · CLICK TWO NODES', 3200);
    }
  }

  function toggleLinkFrom(id) {
    const key = pathKey(findNode(id));
    if (!S.linkSource) {
      S.linkSource = key;
      for (const [nid, el] of S.nodeEls) {
        el.classList.toggle('is-link-source', nid === id);
        el.classList.remove('is-link-target');
      }
      toast('LINK SOURCE SET · CLICK THE OTHER NODE', 2600);
      return;
    }
    if (S.linkSource === key) {
      S.linkSource = null;
      for (const el of S.nodeEls.values()) el.classList.remove('is-link-source', 'is-link-target');
      toast('LINK CANCELLED');
      return;
    }
    const links = loadLinks();
    const duplicate = links.some(l =>
      (l.a === S.linkSource && l.b === key) || (l.a === key && l.b === S.linkSource)
    );
    if (!duplicate) {
      links.push({ a: S.linkSource, b: key, at: Date.now() });
      saveLinks(links);
      toast('FREEFORM LINK DRAWN · RIGHT-CLICK TO REMOVE', 3000);
    } else {
      toast('THAT LINK ALREADY EXISTS');
    }
    S.linkSource = null;
    for (const el of S.nodeEls.values()) el.classList.remove('is-link-source', 'is-link-target');
    redrawCurrentScene();
  }

  function removeLink(a, b) {
    const links = loadLinks().filter(l => !(l.a === a && l.b === b) && !(l.a === b && l.b === a));
    saveLinks(links);
    redrawCurrentScene();
    toast('LINK REMOVED');
  }

  function redrawCurrentScene() {
    if (!S.scene) return;
    S.selected = null;
    S.hovered = null;
    closeInspector();
    renderScene();
    S.cams[S.view] = { ...S.cam };
  }

  // ------------------------------------------------------------------
  // heartbeat / browser lifecycle

  const SID = (() => {
    let id = sessionStorage.getItem('config-canvas-sid');
    if (!id) {
      id = (crypto.randomUUID?.() || Math.random().toString(36).slice(2) + Date.now().toString(36));
      sessionStorage.setItem('config-canvas-sid', id);
    }
    return id;
  })();

  function setLive(online, text) {
    els.live.classList.toggle('is-online', online);
    els.liveText.textContent = text || (online ? 'LIVE' : 'OFFLINE');
    if (online) {
      els.live.classList.remove('is-pulse');
      void els.live.offsetWidth;
      els.live.classList.add('is-pulse');
    }
  }

  async function heartbeat() {
    try {
      const res = await fetch('/api/heartbeat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sid: SID }),
        cache: 'no-store',
        keepalive: true,
      });
      setLive(res.ok, res.ok ? 'LIVE' : 'OFFLINE');
    } catch {
      setLive(false, 'OFFLINE');
    }
  }

  function leave() {
    try {
      const blob = new Blob([JSON.stringify({ sid: SID })], { type: 'application/json' });
      navigator.sendBeacon('/api/leave?sid=' + encodeURIComponent(SID), blob);
    } catch { /* ignore */ }
  }

  function startLifecycle() {
    heartbeat();
    setInterval(heartbeat, 2500);
    try {
      const es = new EventSource('/api/events?sid=' + encodeURIComponent(SID));
      es.addEventListener('open', () => setLive(true, 'LIVE'));
      es.addEventListener('hello', () => setLive(true, 'LIVE'));
      es.addEventListener('error', () => { /* browser retries; heartbeat is the fallback */ });
    } catch { /* ignore */ }
    window.addEventListener('pagehide', leave, { once: true });
    window.addEventListener('beforeunload', leave, { once: true });
  }

  // ------------------------------------------------------------------
  // data loading

  async function loadGraph(opts = {}) {
    const firstLoad = !S.fs;
    const previousCam = S.cams.files ? { ...S.cams.files } : null;
    if (!opts.quiet) {
      showLoading('scanning ' + 'the folder…');
      els.loadingSub.textContent = 'reading the folder…';
    }
    try {
      const res = await fetch('/api/graph?refresh=1', { cache: 'no-store' });
      if (!res.ok) throw new Error('scan request failed: ' + res.status);
      const data = await res.json();
      S.fs = data;
      S.fileScene = null;
      els.rootPath.textContent = data.root;
      els.rootPath.title = data.root;
      populateFileSelect();
      if (S.view === 'files') {
        S.scene = buildFileScene({ fresh: true });
        renderScene();
        if (firstLoad) fitView({ animate: false, maxDepth: 1 });
        else if (previousCam) { S.cam = previousCam; applyCamera(); }
        else fitView({ animate: false, maxDepth: 1 });
        S.cams.files = { ...S.cam };
      } else {
        // refresh the open content file too, if it still exists
        const stillThere = (data.files || []).some(f => f.path === S.contentPath);
        if (stillThere) loadContent(S.contentPath, { keepCamera: false });
        else {
          S.content = null;
          setView('files');
        }
      }
      updateStats();
      if (!opts.quiet) hideLoading();
      if (opts.quiet) {
        toast(`SCANNED · ${fmt(data.stats.nodes)} NODES · ${fmt(data.stats.files)} FILES`, 2600);
      }
    } catch (err) {
      if (!opts.quiet) loadingError('scan failed: ' + err.message);
      else toast('SCAN FAILED · ' + err.message.toUpperCase(), 4000);
    }
  }

  // ------------------------------------------------------------------
  // interactions

  function bindInteractions() {
    els.canvas.addEventListener('pointerdown', (ev) => {
      if (ev.button === 2) {
        // Right-drag is a dedicated pan: it never grabs the node under it.
        ev.preventDefault();
        startPan(ev);
        return;
      }
      if (ev.button !== 0) return;
      const id = nodeFromEvent(ev);
      if (id) {
        ev.preventDefault();
        startNodeDrag(ev, id);
        return;
      }
      if (ev.target.closest?.('.custom-edge')) return;
      startPan(ev);
    });

    els.canvas.addEventListener('pointermove', onPointerMove);
    els.canvas.addEventListener('pointerup', onPointerUp);
    els.canvas.addEventListener('pointercancel', onPointerUp);

    els.canvas.addEventListener('wheel', (ev) => {
      ev.preventDefault();
      const pt = getPointer(ev);
      const factor = Math.exp(-ev.deltaY * (ev.deltaMode === 1 ? 0.035 : 0.0016));
      zoomAt(pt.x, pt.y, factor);
      scheduleMini();
    }, { passive: false });

    els.canvas.addEventListener('dblclick', (ev) => {
      const link = ev.target.closest?.('.custom-edge');
      if (link) {
        ev.preventDefault();
        const [a, b] = (link.getAttribute('data-key') || '').split('|');
        if (a && b) removeLink(a, b);
        return;
      }
      const id = nodeFromEvent(ev);
      if (!id || S.view !== 'content') return;
      ev.preventDefault();
      toggleFold(id);
    });

    els.canvas.addEventListener('contextmenu', (ev) => {
      ev.preventDefault();
    });

    window.addEventListener('resize', () => {
      applyCamera();
      updateMiniViewport();
    });

    els.minimap.addEventListener('click', minimapJump);

    els.search.addEventListener('input', debounce(() => {
      S.search = els.search.value;
      runSearch({ jump: false });
    }, 90));
    els.search.addEventListener('keydown', (ev) => {
      if (ev.key === 'Enter') {
        ev.preventDefault();
        runSearch({ jump: true });
      }
      if (ev.key === 'Escape') {
        els.search.value = '';
        S.search = '';
        runSearch();
        els.search.blur();
      }
    });

    $$('.switch-btn').forEach(btn => btn.addEventListener('click', () => setView(btn.dataset.view)));
    els.btnFit.addEventListener('click', () => fitView());
    els.btnLink.addEventListener('click', () => toggleLinkMode());
    els.btnArrange.addEventListener('click', () => arrangeMap());
    els.btnRefresh.addEventListener('click', () => loadGraph({ quiet: true }));
    $('#btnHelp').addEventListener('click', () => toggleHelp(true));
    $('#helpClose').addEventListener('click', () => toggleHelp(false));
    els.help.addEventListener('click', (ev) => { if (ev.target === els.help) toggleHelp(false); });
    els.inspClose.addEventListener('click', () => clearSelection());
    els.inspector.addEventListener('pointerenter', () => {
      S.inspectorHover = true;
      cancelInfoClose();
    });
    els.inspector.addEventListener('pointerleave', () => {
      S.inspectorHover = false;
      scheduleInfoClose();
    });

    $('#btnExpand').addEventListener('click', () => {
      if (!S.content) return;
      S.contentCollapsed.clear();
      buildAndShowContent({ keepCamera: true });
      fitView({ animate: true });
      els.contentMeta.textContent = `${S.content.tree.stats.nodes} nodes · ${visibleCount()} visible · depth ${S.content.tree.stats.maxDepth}`;
    });
    $('#btnFold').addEventListener('click', () => {
      if (!S.content) return;
      S.contentCollapsed = new Set();
      countTree(S.content.tree);
      const walk = (node, depth) => {
        if ((node.children || []).length && depth >= 2) S.contentCollapsed.add(node.id);
        if (depth < 2) for (const c of node.children || []) walk(c, depth + 1);
      };
      walk(S.content.tree, 0);
      buildAndShowContent({ keepCamera: true });
      fitView({ animate: true });
      els.contentMeta.textContent = `${S.content.tree.stats.nodes} nodes · ${visibleCount()} visible · depth ${S.content.tree.stats.maxDepth}`;
    });
    els.fileSelect.addEventListener('change', () => {
      if (els.fileSelect.value) loadContent(els.fileSelect.value);
      els.fileSelect.blur();
    });

    document.addEventListener('keydown', (ev) => {
      const tag = (ev.target.tagName || '').toLowerCase();
      const typing = tag === 'input' || tag === 'textarea' || tag === 'select';
      if (typing) {
        if (ev.key === 'Escape') ev.target.blur();
        return;
      }
      if (ev.key === 'Escape') {
        if (!els.help.hidden) { toggleHelp(false); return; }
        if (S.linkMode) { toggleLinkMode(false); return; }
        clearSelection();
        return;
      }
      if (ev.key === '/') {
        ev.preventDefault();
        els.search.focus();
        els.search.select();
        return;
      }
      if (ev.key === '?' || (ev.key === '/' && ev.shiftKey)) {
        ev.preventDefault();
        toggleHelp();
        return;
      }
      switch (ev.key.toLowerCase()) {
        case 'f': ev.preventDefault(); fitView(); break;
        case 'a': ev.preventDefault(); arrangeMap(); break;
        case 'l': ev.preventDefault(); toggleLinkMode(); break;
        case 'r': ev.preventDefault(); loadGraph({ quiet: true }); break;
        case '1': ev.preventDefault(); setView('files'); break;
        case '2': ev.preventDefault(); setView('content'); break;
        case '+': case '=': ev.preventDefault(); zoomAt(viewportSize().w / 2, viewportSize().h / 2, 1.15); break;
        case '-': case '_': ev.preventDefault(); zoomAt(viewportSize().w / 2, viewportSize().h / 2, 1 / 1.15); break;
        default: break;
      }
    });

    window.addEventListener('error', (ev) => {
      console.error(ev.error || ev.message);
    });
  }

  // ------------------------------------------------------------------
  // boot

  async function boot() {
    bindInteractions();
    startLifecycle();
    applyCamera();
    await loadGraph();
    if (S.fs) {
      setTimeout(() => {
        if (S.view === 'files') toast(`${fmt(S.fs.stats.nodes)} NODES · DRAG TO ROAM · F FITS ALL`, 3200);
      }, 900);
    }
    if (window.location.hash.startsWith('#content/')) {
      const path = decodeURIComponent(window.location.hash.slice('#content/'.length));
      if (path) {
        setView('content');
        loadContent(path);
      }
    }
  }

  boot();
})();
