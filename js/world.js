'use strict';

// ---------------------------------------------------------------------------
// Carte : génération du terrain, occupation des cases, recherche de chemin
// ---------------------------------------------------------------------------

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Centre (en cases) du QG de chaque camp. La carte est symétrique par rapport au centre.
const BASE_TILES = [
  { x: 9, y: MAP_H - 10 },
  { x: MAP_W - 10, y: 9 },
];

// Coins haut-gauche des mines d'or côté joueur (le côté ennemi est obtenu par symétrie).
const MINE_SPOTS = [
  { x: 15, y: 48, gold: 2500 },
  { x: 16, y: 57, gold: 2500 },
  { x: 30, y: 38, gold: 4000 },
  { x: 8, y: 30, gold: 4000 },
  { x: 44, y: 24, gold: 5000 },
];

function mirrorX(x, w) { return MAP_W - x - (w || 1); }
function mirrorY(y, h) { return MAP_H - y - (h || 1); }
function inMap(tx, ty) { return tx >= 0 && ty >= 0 && tx < MAP_W && ty < MAP_H; }
function tileIdx(tx, ty) { return ty * MAP_W + tx; }

function generateTerrain(seed) {
  for (let attempt = 0; attempt < 40; attempt++) {
    const terrain = tryGenerate(seed + attempt * 7919);
    if (terrainIsValid(terrain)) return terrain;
  }
  // Solution de repli : carte vide.
  return new Uint8Array(MAP_W * MAP_H);
}

function tryGenerate(seed) {
  const rng = mulberry32(seed);
  const terrain = new Uint8Array(MAP_W * MAP_H);

  const stamp = (tx, ty, t) => {
    if (!inMap(tx, ty)) return;
    terrain[tileIdx(tx, ty)] = t;
    terrain[tileIdx(mirrorX(tx), mirrorY(ty))] = t;
  };
  const blob = (cx, cy, r, t, density) => {
    const parts = 2 + Math.floor(rng() * 3);
    for (let p = 0; p < parts; p++) {
      const ox = cx + (rng() - 0.5) * r * 1.6;
      const oy = cy + (rng() - 0.5) * r * 1.6;
      const rr = r * (0.6 + rng() * 0.5);
      for (let y = Math.floor(oy - rr); y <= oy + rr; y++) {
        for (let x = Math.floor(ox - rr); x <= ox + rr; x++) {
          const d = Math.hypot(x - ox, y - oy);
          if (d <= rr && rng() < density) stamp(x, y, t);
        }
      }
    }
  };

  // Lacs
  const lakes = 3 + Math.floor(rng() * 2);
  for (let i = 0; i < lakes; i++) {
    blob(Math.floor(rng() * MAP_W), Math.floor(rng() * MAP_H), 2.5 + rng() * 3, T_WATER, 1);
  }
  // Forêts
  const forests = 9 + Math.floor(rng() * 5);
  for (let i = 0; i < forests; i++) {
    blob(Math.floor(rng() * MAP_W), Math.floor(rng() * MAP_H), 2 + rng() * 3, T_FOREST, 0.85);
  }
  // Arbres épars le long des bords
  for (let x = 0; x < MAP_W; x++) {
    for (let d = 0; d < 2; d++) {
      if (rng() < 0.45 - d * 0.2) stamp(x, d, T_FOREST);
      if (rng() < 0.45 - d * 0.2) stamp(d, Math.floor(rng() * MAP_H), T_FOREST);
    }
  }

  // Dégager les bases et les mines
  const clear = (cx, cy, r) => {
    for (let y = Math.floor(cy - r); y <= cy + r; y++) {
      for (let x = Math.floor(cx - r); x <= cx + r; x++) {
        if (Math.hypot(x - cx, y - cy) <= r) stamp(x, y, T_GRASS);
      }
    }
  };
  clear(BASE_TILES[0].x, BASE_TILES[0].y, 10);
  for (const m of MINE_SPOTS) clear(m.x + 0.5, m.y + 0.5, 3.5);
  return terrain;
}

function terrainIsValid(terrain) {
  // Parcours en largeur depuis la base du joueur : la base ennemie et toutes les mines doivent être atteignables.
  const seen = new Uint8Array(MAP_W * MAP_H);
  const start = tileIdx(BASE_TILES[0].x, BASE_TILES[0].y);
  const queue = [start];
  seen[start] = 1;
  let count = 0;
  while (queue.length) {
    const i = queue.pop();
    count++;
    const x = i % MAP_W, y = (i / MAP_W) | 0;
    for (let d = 0; d < 4; d++) {
      const nx = x + (d === 0 ? 1 : d === 1 ? -1 : 0);
      const ny = y + (d === 2 ? 1 : d === 3 ? -1 : 0);
      if (!inMap(nx, ny)) continue;
      const ni = tileIdx(nx, ny);
      if (seen[ni] || terrain[ni] !== T_GRASS) continue;
      seen[ni] = 1;
      queue.push(ni);
    }
  }
  if (!seen[tileIdx(BASE_TILES[1].x, BASE_TILES[1].y)]) return false;
  let grass = 0;
  for (let i = 0; i < terrain.length; i++) if (terrain[i] === T_GRASS) grass++;
  // Évite les poches de terrain isolées trop grandes.
  return count > grass * 0.9;
}

// Occupation ----------------------------------------------------------------

function isWalkable(tx, ty) {
  if (!inMap(tx, ty)) return false;
  const i = tileIdx(tx, ty);
  return G.terrain[i] === T_GRASS && G.occ[i] === 0;
}

function isWalkableWorld(x, y) {
  return isWalkable(Math.floor(x / TILE), Math.floor(y / TILE));
}

function setOccupancy(e, value) {
  for (let y = e.ty; y < e.ty + e.th; y++) {
    for (let x = e.tx; x < e.tx + e.tw; x++) {
      if (inMap(x, y)) G.occ[tileIdx(x, y)] = value;
    }
  }
}

function canPlaceBuilding(type, tx, ty, team) {
  const def = BUILDING_TYPES[type];
  for (let y = ty; y < ty + def.h; y++) {
    for (let x = tx; x < tx + def.w; x++) {
      if (!isWalkable(x, y)) return false;
      if (team === PLAYER && !G.explored[tileIdx(x, y)]) return false;
    }
  }
  // Pas d'unité ennemie sur l'emplacement ; les unités alliées seront poussées.
  const x0 = tx * TILE, y0 = ty * TILE, x1 = (tx + def.w) * TILE, y1 = (ty + def.h) * TILE;
  for (const u of G.units) {
    if (u.team === team) continue;
    if (u.x + u.radius > x0 && u.x - u.radius < x1 && u.y + u.radius > y0 && u.y - u.radius < y1) return false;
  }
  // Éviter de coller un bâtiment directement contre une mine (gêne la récolte).
  for (const m of G.mines) {
    if (tx < m.tx + m.tw + 1 && tx + def.w > m.tx - 1 && ty < m.ty + m.th + 1 && ty + def.h > m.ty - 1) return false;
  }
  return true;
}

function nearestWalkableTile(tx, ty, maxR) {
  if (isWalkable(tx, ty)) return { x: tx, y: ty };
  maxR = maxR || 20;
  for (let r = 1; r <= maxR; r++) {
    let best = null, bestD = Infinity;
    for (let y = ty - r; y <= ty + r; y++) {
      for (let x = tx - r; x <= tx + r; x++) {
        if (Math.max(Math.abs(x - tx), Math.abs(y - ty)) !== r) continue;
        if (!isWalkable(x, y)) continue;
        const d = (x - tx) * (x - tx) + (y - ty) * (y - ty);
        if (d < bestD) { bestD = d; best = { x, y }; }
      }
    }
    if (best) return best;
  }
  return null;
}

// Recherche de chemin (A*) ----------------------------------------------------

const PF = {
  g: new Float32Array(MAP_W * MAP_H),
  from: new Int32Array(MAP_W * MAP_H),
  stamp: new Uint32Array(MAP_W * MAP_H),
  closed: new Uint32Array(MAP_W * MAP_H),
  cur: 0,
  heap: [],
  heapF: [],
};

function heapPush(i, f) {
  const h = PF.heap, hf = PF.heapF;
  let n = h.length;
  h.push(i); hf.push(f);
  while (n > 0) {
    const p = (n - 1) >> 1;
    if (hf[p] <= f) break;
    h[n] = h[p]; hf[n] = hf[p];
    n = p;
  }
  h[n] = i; hf[n] = f;
}

function heapPop() {
  const h = PF.heap, hf = PF.heapF;
  const top = h[0];
  const li = h.pop(), lf = hf.pop();
  const len = h.length;
  if (len > 0) {
    let n = 0;
    while (true) {
      let c = 2 * n + 1;
      if (c >= len) break;
      if (c + 1 < len && hf[c + 1] < hf[c]) c++;
      if (hf[c] >= lf) break;
      h[n] = h[c]; hf[n] = hf[c];
      n = c;
    }
    h[n] = li; hf[n] = lf;
  }
  return top;
}

const DIRS = [
  [1, 0, 1], [-1, 0, 1], [0, 1, 1], [0, -1, 1],
  [1, 1, 1.4142], [1, -1, 1.4142], [-1, 1, 1.4142], [-1, -1, 1.4142],
];

// goal : { x, y } (case) ou { rect: {tx, ty, tw, th} } (atteindre une case adjacente)
function astar(sx, sy, goal) {
  PF.cur++;
  if (PF.cur > 4000000000) { PF.cur = 1; PF.stamp.fill(0); PF.closed.fill(0); }
  const cur = PF.cur;
  PF.heap.length = 0; PF.heapF.length = 0;

  let gx, gy, isGoal;
  if (goal.rect) {
    const r = goal.rect;
    gx = r.tx + (r.tw - 1) / 2; gy = r.ty + (r.th - 1) / 2;
    isGoal = (x, y) => x >= r.tx - 1 && x <= r.tx + r.tw && y >= r.ty - 1 && y <= r.ty + r.th;
  } else {
    gx = goal.x; gy = goal.y;
    isGoal = (x, y) => x === goal.x && y === goal.y;
  }
  const h = (x, y) => {
    const dx = Math.abs(x - gx), dy = Math.abs(y - gy);
    return Math.max(dx, dy) + 0.4142 * Math.min(dx, dy);
  };

  const start = tileIdx(sx, sy);
  PF.g[start] = 0; PF.from[start] = -1; PF.stamp[start] = cur;
  heapPush(start, h(sx, sy));
  let best = start, bestH = h(sx, sy);
  let found = -1;
  let expanded = 0;

  while (PF.heap.length) {
    const i = heapPop();
    if (PF.closed[i] === cur) continue;
    PF.closed[i] = cur;
    const x = i % MAP_W, y = (i / MAP_W) | 0;
    if (isGoal(x, y)) { found = i; break; }
    const hh = h(x, y);
    if (hh < bestH) { bestH = hh; best = i; }
    if (++expanded > 9000) break;
    const gi = PF.g[i];
    for (let d = 0; d < 8; d++) {
      const nx = x + DIRS[d][0], ny = y + DIRS[d][1];
      if (!isWalkable(nx, ny)) continue;
      if (d >= 4 && (!isWalkable(x + DIRS[d][0], y) || !isWalkable(x, y + DIRS[d][1]))) continue;
      const ni = tileIdx(nx, ny);
      if (PF.closed[ni] === cur) continue;
      const ng = gi + DIRS[d][2];
      if (PF.stamp[ni] !== cur || ng < PF.g[ni]) {
        PF.stamp[ni] = cur;
        PF.g[ni] = ng;
        PF.from[ni] = i;
        heapPush(ni, ng + h(nx, ny) * 1.001);
      }
    }
  }

  const end = found >= 0 ? found : best;
  const tiles = [];
  for (let i = end; i !== -1; i = PF.from[i]) {
    tiles.push(i);
    if (i === start) break;
  }
  tiles.reverse();
  return { tiles, reached: found >= 0 };
}

function lineWalkable(x0, y0, x1, y1, radius) {
  const d = Math.hypot(x1 - x0, y1 - y0);
  const steps = Math.ceil(d / 8);
  for (let s = 1; s <= steps; s++) {
    const t = s / steps;
    const x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t;
    if (!isWalkableWorld(x, y)) return false;
    if (radius) {
      if (!isWalkableWorld(x + radius, y) || !isWalkableWorld(x - radius, y) ||
          !isWalkableWorld(x, y + radius) || !isWalkableWorld(x, y - radius)) return false;
    }
  }
  return true;
}

// Renvoie une liste de points (monde) de (x,y) vers la cible.
// target : { x, y } en coordonnées monde, ou { rect }.
function findPath(x, y, target, radius) {
  let sx = Math.floor(x / TILE), sy = Math.floor(y / TILE);
  if (!isWalkable(sx, sy)) {
    const n = nearestWalkableTile(sx, sy, 6);
    if (!n) return [];
    sx = n.x; sy = n.y;
  }
  let goal, finalPoint = null;
  if (target.rect) {
    goal = { rect: target.rect };
  } else {
    let gx = Math.floor(target.x / TILE), gy = Math.floor(target.y / TILE);
    gx = Math.max(0, Math.min(MAP_W - 1, gx));
    gy = Math.max(0, Math.min(MAP_H - 1, gy));
    if (!isWalkable(gx, gy)) {
      const n = nearestWalkableTile(gx, gy, 12);
      if (!n) return [];
      gx = n.x; gy = n.y;
    } else {
      finalPoint = { x: target.x, y: target.y };
    }
    goal = { x: gx, y: gy };
  }
  const res = astar(sx, sy, goal);
  const pts = res.tiles.map(i => ({ x: (i % MAP_W) * TILE + TILE / 2, y: ((i / MAP_W) | 0) * TILE + TILE / 2 }));
  if (res.reached && finalPoint) {
    if (pts.length) pts[pts.length - 1] = finalPoint; else pts.push(finalPoint);
  }
  // Lissage du chemin (tirage de ficelle)
  const out = [];
  let ax = x, ay = y, i = 0;
  while (i < pts.length) {
    let j = pts.length - 1;
    while (j > i && !lineWalkable(ax, ay, pts[j].x, pts[j].y, radius * 0.8)) j--;
    out.push(pts[j]);
    ax = pts[j].x; ay = pts[j].y;
    i = j + 1;
  }
  return out;
}
