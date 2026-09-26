'use strict';

// ---------------------------------------------------------------------------
// Monde : génération, collisions, champ de déplacement des ombres
// ---------------------------------------------------------------------------

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const T_GRASS = 0, T_WATER = 1;
const HEARTH_TX = MAP_W / 2 - 1, HEARTH_TY = MAP_H / 2 - 1; // le foyer occupe 2x2 cases
const HEARTH_X = (HEARTH_TX + 1) * TILE, HEARTH_Y = (HEARTH_TY + 1) * TILE;

function inMap(tx, ty) { return tx >= 0 && ty >= 0 && tx < MAP_W && ty < MAP_H; }
function idx(tx, ty) { return ty * MAP_W + tx; }
function tileOf(v) { return Math.floor(v / TILE); }

// Bruit de valeur lissé pour des formes organiques
function makeNoise(rng, cell) {
  const gw = Math.ceil(MAP_W / cell) + 2, gh = Math.ceil(MAP_H / cell) + 2;
  const g = new Float32Array(gw * gh).map(() => rng());
  const s = t => t * t * (3 - 2 * t);
  return (x, y) => {
    const fx = x / cell, fy = y / cell;
    const x0 = Math.floor(fx), y0 = Math.floor(fy);
    const tx = s(fx - x0), ty = s(fy - y0);
    const a = g[y0 * gw + x0], b = g[y0 * gw + x0 + 1];
    const c = g[(y0 + 1) * gw + x0], d = g[(y0 + 1) * gw + x0 + 1];
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty;
  };
}

function generateWorld(seed) {
  const rng = mulberry32(seed);
  const terrain = new Uint8Array(MAP_W * MAP_H);
  const water = makeNoise(rng, 9);
  const forest = makeNoise(rng, 6);
  const nodes = [];
  const cx = HEARTH_TX + 1, cy = HEARTH_TY + 1;

  for (let y = 0; y < MAP_H; y++) {
    for (let x = 0; x < MAP_W; x++) {
      const d = Math.hypot(x - cx, y - cy);
      const edge = Math.min(x, y, MAP_W - 1 - x, MAP_H - 1 - y);
      if (edge < 2) { terrain[idx(x, y)] = T_WATER; continue; }
      if (d > 9 && water(x, y) > 0.76) terrain[idx(x, y)] = T_WATER;
    }
  }
  const taken = new Uint8Array(MAP_W * MAP_H);
  const place = (type, x, y) => {
    if (!inMap(x, y) || terrain[idx(x, y)] !== T_GRASS || taken[idx(x, y)]) return false;
    taken[idx(x, y)] = 1;
    nodes.push({ type, tx: x, ty: y });
    return true;
  };
  for (let y = 2; y < MAP_H - 2; y++) {
    for (let x = 2; x < MAP_W - 2; x++) {
      const d = Math.hypot(x - cx, y - cy);
      if (d < 5.5) continue;
      const f = forest(x, y);
      const density = d < 10 ? 0.05 : 0.12 + Math.min(0.5, (f - 0.45) * 1.6);
      const r = rng();
      if (r < density && f > 0.4) place('tree', x, y);
      else if (r > 0.978 - (d > 14 ? 0.012 : 0)) place('rock', x, y);
    }
  }
  // Cristaux de braise : loin du foyer, dans les ténèbres
  let crystals = 0;
  for (let tries = 0; tries < 400 && crystals < 14; tries++) {
    const a = rng() * Math.PI * 2, d = 16 + rng() * 16;
    const x = Math.round(cx + Math.cos(a) * d), y = Math.round(cy + Math.sin(a) * d);
    if (place('crystal', x, y)) crystals++;
  }
  // Quelques rochers garantis près du camp
  for (let i = 0; i < 6; i++) {
    const a = i / 6 * Math.PI * 2 + rng();
    place('rock', Math.round(cx + Math.cos(a) * 8), Math.round(cy + Math.sin(a) * 8));
  }
  return { terrain, nodes };
}

// Collisions -------------------------------------------------------------------

function tileSolid(tx, ty) {
  if (!inMap(tx, ty)) return true;
  const i = idx(tx, ty);
  if (G.terrain[i] === T_WATER) return true;
  const id = G.grid[i];
  if (!id) return false;
  const e = G.ents.get(id);
  return !!e && e.solid;
}

function circleHitsSolid(x, y, r) {
  const x0 = tileOf(x - r), x1 = tileOf(x + r), y0 = tileOf(y - r), y1 = tileOf(y + r);
  for (let ty = y0; ty <= y1; ty++) {
    for (let tx = x0; tx <= x1; tx++) {
      if (!tileSolid(tx, ty)) continue;
      const px = Math.max(tx * TILE, Math.min(x, (tx + 1) * TILE));
      const py = Math.max(ty * TILE, Math.min(y, (ty + 1) * TILE));
      if ((px - x) * (px - x) + (py - y) * (py - y) < r * r) return true;
    }
  }
  return false;
}

// Déplacement avec glissement le long des obstacles
function moveCircle(e, dx, dy) {
  // colR : rayon de collision avec le décor (les grosses ombres se faufilent entre les arbres)
  const r = e.colR || e.radius;
  if (dx && !circleHitsSolid(e.x + dx, e.y, r)) e.x += dx;
  if (dy && !circleHitsSolid(e.x, e.y + dy, r)) e.y += dy;
  e.x = Math.max(e.radius, Math.min(WORLD_W - e.radius, e.x));
  e.y = Math.max(e.radius, Math.min(WORLD_H - e.radius, e.y));
}

// Ligne de vue dégagée entre deux points (aucune case bloquante)
function lineClear(x0, y0, x1, y1) {
  const d = Math.hypot(x1 - x0, y1 - y0);
  const steps = Math.ceil(d / 14);
  for (let i = 1; i < steps; i++) {
    const t = i / steps;
    if (tileSolid(tileOf(x0 + (x1 - x0) * t), tileOf(y0 + (y1 - y0) * t))) return false;
  }
  return true;
}

// Champ de distances vers le foyer (Dijkstra). Les constructions sont franchissables
// à coût élevé : les ombres les attaquent pour passer.
function computeFlowField() {
  const N = MAP_W * MAP_H;
  const dist = G.flow || new Float32Array(N);
  dist.fill(Infinity);
  const heap = [], hf = [];
  const push = (i, f) => {
    let n = heap.length; heap.push(i); hf.push(f);
    while (n > 0) { const p = (n - 1) >> 1; if (hf[p] <= f) break; heap[n] = heap[p]; hf[n] = hf[p]; n = p; }
    heap[n] = i; hf[n] = f;
  };
  const pop = () => {
    const top = heap[0], li = heap.pop(), lf = hf.pop();
    if (heap.length) {
      let n = 0; const len = heap.length;
      while (true) {
        let c = 2 * n + 1; if (c >= len) break;
        if (c + 1 < len && hf[c + 1] < hf[c]) c++;
        if (hf[c] >= lf) break;
        heap[n] = heap[c]; hf[n] = hf[c]; n = c;
      }
      heap[n] = li; hf[n] = lf;
    }
    return top;
  };
  for (let y = HEARTH_TY; y < HEARTH_TY + 2; y++) {
    for (let x = HEARTH_TX; x < HEARTH_TX + 2; x++) { dist[idx(x, y)] = 0; push(idx(x, y), 0); }
  }
  const cost = (tx, ty) => {
    const i = idx(tx, ty);
    if (G.terrain[i] === T_WATER) return Infinity;
    const id = G.grid[i];
    if (!id) return 1;
    const e = G.ents.get(id);
    if (!e) return 1;
    if (e.kind === 'node') return Infinity;
    if (e.kind === 'hearth') return 1;
    return e.solid ? 7 : 1.5;
  };
  while (heap.length) {
    const i = pop();
    const x = i % MAP_W, y = (i / MAP_W) | 0;
    const d = dist[i];
    for (let k = 0; k < 8; k++) {
      const ox = [1, -1, 0, 0, 1, 1, -1, -1][k], oy = [0, 0, 1, -1, 1, -1, 1, -1][k];
      const nx = x + ox, ny = y + oy;
      if (!inMap(nx, ny)) continue;
      if (k >= 4 && (cost(x + ox, y) === Infinity || cost(x, y + oy) === Infinity)) continue;
      const c = cost(nx, ny);
      if (c === Infinity) continue;
      const nd = d + c * (k >= 4 ? 1.414 : 1);
      const ni = idx(nx, ny);
      if (nd < dist[ni]) { dist[ni] = nd; push(ni, nd); }
    }
  }
  G.flow = dist;
  G.flowDirty = false;
}

// Case voisine qui rapproche le plus du foyer
function nextFlowTile(tx, ty) {
  let best = null, bestD = G.flow[idx(tx, ty)];
  for (let k = 0; k < 8; k++) {
    const ox = [1, -1, 0, 0, 1, 1, -1, -1][k], oy = [0, 0, 1, -1, 1, -1, 1, -1][k];
    const nx = tx + ox, ny = ty + oy;
    if (!inMap(nx, ny)) continue;
    if (k >= 4 && (G.flow[idx(tx + ox, ty)] === Infinity || G.flow[idx(tx, ty + oy)] === Infinity)) continue;
    const d = G.flow[idx(nx, ny)];
    if (d < bestD) { bestD = d; best = { x: nx, y: ny }; }
  }
  return best;
}
