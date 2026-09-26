'use strict';

// ---------------------------------------------------------------------------
// État du jeu, entités, ordres, combat
// ---------------------------------------------------------------------------

let G = null;

function newGame(difficulty, seed) {
  const diff = DIFFICULTIES[difficulty] || DIFFICULTIES.normal;
  seed = seed || (Math.random() * 1e9) | 0;
  G = {
    difficulty,
    diff,
    seed,
    time: 0,
    nextId: 1,
    terrain: generateTerrain(seed),
    occ: new Int32Array(MAP_W * MAP_H),
    visible: new Uint8Array(MAP_W * MAP_H),
    explored: new Uint8Array(MAP_W * MAP_H),
    units: [],
    buildings: [],
    mines: [],
    projectiles: [],
    effects: [],
    byId: new Map(),
    teams: [
      { gold: diff.startGold, gatherMult: 1, stats: newStats() },
      { gold: diff.startGold, gatherMult: diff.gatherMult, stats: newStats() },
    ],
    selection: [],
    groups: {},
    messages: [],
    over: null,
    paused: false,
    fogTimer: 0,
    attackAlertTimer: 0,
  };

  // Mines d'or (symétriques)
  for (const m of MINE_SPOTS) {
    addMine(m.x, m.y, m.gold);
    addMine(mirrorX(m.x, MINE_W), mirrorY(m.y, MINE_H), m.gold);
  }

  // Bases de départ
  for (let team = 0; team < 2; team++) {
    const b = BASE_TILES[team];
    const hq = addBuilding('hq', team, b.x - 1, b.y - 1, true);
    const dir = team === PLAYER ? 1 : -1;
    for (let i = 0; i < 5; i++) {
      const u = addUnit('worker', team, hq.x + dir * (70 + (i % 3) * 22), hq.y - dir * (30 - Math.floor(i / 3) * 40));
      unstick(u);
    }
    addUnit('spearman', team, hq.x - dir * 60, hq.y - dir * 60);
    addUnit('archer', team, hq.x - dir * 30, hq.y - dir * 75);
  }
  for (const u of G.units) {
    unstick(u);
    if (u.type === 'worker') issueOrder(u, { type: 'harvest', mine: nearestMine(u.x, u.y) });
  }
  updateFog();
  return G;
}

function newStats() {
  return { trained: 0, lost: 0, killed: 0, gathered: 0, buildingsLost: 0, buildingsDestroyed: 0 };
}

// Création des entités -------------------------------------------------------

function addUnit(type, team, x, y) {
  const def = UNIT_TYPES[type];
  const u = {
    id: G.nextId++, kind: 'unit', type, team, def,
    x, y, radius: def.radius,
    hp: def.hp, maxHp: def.hp,
    order: null, path: [], pathTarget: null, repathTimer: 0,
    target: null, cooldown: 0, scanTimer: Math.random() * 0.3,
    carry: 0, gatherTimer: 0, lastMine: null,
    facing: team === PLAYER ? -Math.PI / 4 : Math.PI * 3 / 4, attackAnim: 0,
    stuckTimer: 0, lastDist: Infinity, dead: false,
  };
  G.units.push(u);
  G.byId.set(u.id, u);
  return u;
}

function addBuilding(type, team, tx, ty, complete) {
  const def = BUILDING_TYPES[type];
  const b = {
    id: G.nextId++, kind: 'building', type, team, def,
    tx, ty, tw: def.w, th: def.h,
    x: (tx + def.w / 2) * TILE, y: (ty + def.h / 2) * TILE,
    radius: Math.max(def.w, def.h) * TILE / 2,
    maxHp: def.hp, hp: complete ? def.hp : Math.max(1, def.hp * 0.1),
    complete: !!complete, progress: complete ? 1 : 0,
    queue: [], rally: null, cooldown: 0, target: null, scanTimer: 0,
    dead: false, seen: team === PLAYER,
  };
  G.buildings.push(b);
  G.byId.set(b.id, b);
  setOccupancy(b, b.id);
  // Pousser les unités qui se trouvent sur l'emplacement
  for (const u of G.units) unstick(u);
  return b;
}

function addMine(tx, ty, gold) {
  const m = {
    id: G.nextId++, kind: 'mine', type: 'mine', team: -1,
    tx, ty, tw: MINE_W, th: MINE_H,
    x: (tx + MINE_W / 2) * TILE, y: (ty + MINE_H / 2) * TILE,
    radius: MINE_W * TILE / 2, gold, maxGold: gold, dead: false,
  };
  G.mines.push(m);
  G.byId.set(m.id, m);
  setOccupancy(m, m.id);
  return m;
}

function unstick(u) {
  const tx = Math.floor(u.x / TILE), ty = Math.floor(u.y / TILE);
  if (isWalkable(tx, ty)) return;
  const n = nearestWalkableTile(tx, ty, 15);
  if (n) {
    u.x = n.x * TILE + TILE / 2 + (Math.random() - 0.5) * 8;
    u.y = n.y * TILE + TILE / 2 + (Math.random() - 0.5) * 8;
    u.path = [];
  }
}

// Utilitaires ----------------------------------------------------------------

function rectOf(e) { return { tx: e.tx, ty: e.ty, tw: e.tw, th: e.th }; }

// Distance entre le bord de l'unité et le bord de la cible.
function edgeDist(u, e) {
  if (e.kind === 'unit') return Math.hypot(e.x - u.x, e.y - u.y) - u.radius - e.radius;
  const x0 = e.tx * TILE, y0 = e.ty * TILE, x1 = (e.tx + e.tw) * TILE, y1 = (e.ty + e.th) * TILE;
  const dx = Math.max(x0 - u.x, 0, u.x - x1);
  const dy = Math.max(y0 - u.y, 0, u.y - y1);
  return Math.hypot(dx, dy) - (u.radius || 0);
}

function teamPop(team) {
  let used = 0, cap = 0;
  for (const u of G.units) if (u.team === team) used += u.def.pop;
  for (const b of G.buildings) {
    if (b.team !== team) continue;
    if (b.complete && b.def.pop) cap += b.def.pop;
    if (b.queue.length && b.queue[0].started) used += UNIT_TYPES[b.queue[0].type].pop;
  }
  return { used, cap: Math.min(cap, MAX_POP) };
}

function hasBuilding(team, type, completeOnly) {
  return G.buildings.some(b => b.team === team && b.type === type && (!completeOnly || b.complete));
}

function isVisibleToPlayer(e) {
  if (e.team === PLAYER) return true;
  if (e.kind === 'unit') {
    const tx = Math.floor(e.x / TILE), ty = Math.floor(e.y / TILE);
    return inMap(tx, ty) && G.visible[tileIdx(tx, ty)] === 1;
  }
  for (let y = e.ty; y < e.ty + e.th; y++) {
    for (let x = e.tx; x < e.tx + e.tw; x++) {
      if (G.visible[tileIdx(x, y)]) return true;
    }
  }
  return false;
}

function notify(text, team) {
  if (team !== undefined && team !== PLAYER) return;
  G.messages.push({ text, t: 3.5 });
  if (G.messages.length > 4) G.messages.shift();
}

// Ordres -----------------------------------------------------------------------

function issueOrder(u, order) {
  u.order = order;
  u.path = [];
  u.pathTarget = null;
  u.target = null;
  u.stuckTimer = 0;
  u.lastDist = Infinity;
  if (order && order.type === 'harvest') u.lastMine = order.mine;
}

// Positions en formation autour d'un point
function formationOffsets(n, spacing) {
  const out = [];
  const cols = Math.ceil(Math.sqrt(n));
  const rows = Math.ceil(n / cols);
  for (let i = 0; i < n; i++) {
    const c = i % cols, r = Math.floor(i / cols);
    out.push({ x: (c - (cols - 1) / 2) * spacing, y: (r - (rows - 1) / 2) * spacing });
  }
  return out;
}

function commandMove(units, x, y, attackMove) {
  if (!units.length) return;
  // Trier par distance pour limiter les croisements.
  let cx = 0, cy = 0;
  for (const u of units) { cx += u.x; cy += u.y; }
  cx /= units.length; cy /= units.length;
  const angle = Math.atan2(y - cy, x - cx);
  const offs = formationOffsets(units.length, 28);
  const cos = Math.cos(angle + Math.PI / 2), sin = Math.sin(angle + Math.PI / 2);
  const rotated = offs.map(o => ({ x: o.x * cos - o.y * sin, y: o.x * sin + o.y * cos }));
  const sorted = units.slice().sort((a, b) => {
    const pa = (a.x - cx) * cos + (a.y - cy) * sin;
    const pb = (b.x - cx) * cos + (b.y - cy) * sin;
    return pa - pb;
  });
  const slots = rotated.slice().sort((a, b) => (a.x * cos + a.y * sin) - (b.x * cos + b.y * sin));
  sorted.forEach((u, i) => {
    let tx = x + (units.length > 1 ? slots[i].x : 0);
    let ty = y + (units.length > 1 ? slots[i].y : 0);
    if (!isWalkableWorld(tx, ty)) { tx = x; ty = y; }
    issueOrder(u, { type: attackMove ? 'attackMove' : 'move', x: tx, y: ty });
  });
}

function commandAttack(units, target) {
  for (const u of units) issueOrder(u, { type: 'attack', target, forced: true });
}

function commandHarvest(units, mine) {
  for (const u of units) {
    if (u.type === 'worker') issueOrder(u, { type: 'harvest', mine });
    else issueOrder(u, { type: 'move', x: mine.x, y: mine.y + mine.radius + 20 });
  }
}

function commandBuild(units, building) {
  for (const u of units) {
    if (u.type === 'worker') issueOrder(u, { type: 'build', building });
  }
}

function commandStop(units) { for (const u of units) issueOrder(u, null); }
function commandHold(units) { for (const u of units) issueOrder(u, { type: 'hold' }); }

function tryPlaceBuilding(team, type, tx, ty, workers) {
  const def = BUILDING_TYPES[type];
  const t = G.teams[team];
  if (def.requires && !hasBuilding(team, def.requires, true)) {
    notify(`Nécessite : ${BUILDING_TYPES[def.requires].name}`, team);
    return null;
  }
  if (t.gold < def.cost) { notify("Sire, nos coffres sont vides : pas assez d'or", team); return null; }
  if (!canPlaceBuilding(type, tx, ty, team)) { notify('Emplacement invalide', team); return null; }
  t.gold -= def.cost;
  const b = addBuilding(type, team, tx, ty, false);
  commandBuild(workers, b);
  return b;
}

function queueTraining(b, type) {
  const t = G.teams[b.team];
  const def = UNIT_TYPES[type];
  if (!b.complete) return false;
  if (b.queue.length >= 5) { notify("File d'attente pleine", b.team); return false; }
  if (t.gold < def.cost) { notify("Sire, nos coffres sont vides : pas assez d'or", b.team); return false; }
  t.gold -= def.cost;
  b.queue.push({ type, t: 0, started: false });
  return true;
}

function cancelTraining(b, index) {
  const item = b.queue[index];
  if (!item) return;
  G.teams[b.team].gold += UNIT_TYPES[item.type].cost;
  b.queue.splice(index, 1);
}

// Mise à jour ------------------------------------------------------------------

function update(dt) {
  if (G.over || G.paused) return;
  G.time += dt;

  for (const u of G.units) if (!u.dead) updateUnit(u, dt);
  separateUnits(dt);
  for (const b of G.buildings) if (!b.dead) updateBuilding(b, dt);
  updateProjectiles(dt);

  for (const e of G.effects) e.t += dt;
  G.effects = G.effects.filter(e => e.t < e.life);
  for (const m of G.messages) m.t -= dt;
  G.messages = G.messages.filter(m => m.t > 0);
  G.attackAlertTimer = Math.max(0, G.attackAlertTimer - dt);

  cleanupDead();

  G.fogTimer -= dt;
  if (G.fogTimer <= 0) { G.fogTimer = 0.2; updateFog(); }

  aiUpdate(dt);
  checkVictory();
}

function cleanupDead() {
  let changed = false;
  for (const list of [G.units, G.buildings, G.mines]) {
    for (const e of list) if (e.dead) changed = true;
  }
  if (!changed) return;
  G.units = G.units.filter(e => !e.dead || (G.byId.delete(e.id), false));
  G.buildings = G.buildings.filter(e => !e.dead || (G.byId.delete(e.id), false));
  G.mines = G.mines.filter(e => !e.dead || (G.byId.delete(e.id), false));
  G.selection = G.selection.filter(e => !e.dead);
  for (const k in G.groups) G.groups[k] = G.groups[k].filter(e => !e.dead);
}

function checkVictory() {
  // Les murailles seules ne suffisent pas à tenir un royaume.
  const alive = [0, 1].map(t => G.buildings.some(b => b.team === t && b.type !== 'wall'));
  if (!alive[ENEMY]) G.over = 'victory';
  else if (!alive[PLAYER]) G.over = 'defeat';
}

// Unités -----------------------------------------------------------------------

function findEnemyNear(u, range) {
  let best = null, bestScore = Infinity;
  const r2 = (range + 60) * (range + 60);
  for (const e of G.units) {
    if (e.team === u.team || e.dead) continue;
    const dx = e.x - u.x, dy = e.y - u.y;
    const d2 = dx * dx + dy * dy;
    if (d2 > r2) continue;
    const d = edgeDist(u, e);
    if (d > range) continue;
    // Préférer les unités combattantes aux ouvriers
    const score = d + (e.type === 'worker' ? 60 : 0);
    if (score < bestScore) { bestScore = score; best = e; }
  }
  if (best) return best;
  for (const b of G.buildings) {
    if (b.team === u.team || b.dead) continue;
    const d = edgeDist(u, b);
    if (d > range) continue;
    const score = d + (b.type === 'tower' ? 0 : b.type === 'wall' ? 160 : 100);
    if (score < bestScore) { bestScore = score; best = b; }
  }
  return best;
}

function moveAlongPath(u, dt, speedMult) {
  if (!u.path.length) return true;
  const p = u.path[0];
  const dx = p.x - u.x, dy = p.y - u.y;
  const d = Math.hypot(dx, dy);
  const step = u.def.speed * (speedMult || 1) * dt;
  u.facing = Math.atan2(dy, dx);
  if (d <= step) {
    u.x = p.x; u.y = p.y;
    u.path.shift();
    return u.path.length === 0;
  }
  const nx = u.x + dx / d * step, ny = u.y + dy / d * step;
  if (!isWalkableWorld(nx, ny)) {
    // Obstacle apparu sur le chemin (ex. nouveau bâtiment) : recalculer.
    u.path = [];
    u.pathTarget = null;
    return false;
  }
  u.x = nx; u.y = ny;
  return false;
}

// Déplace l'unité vers un point ou un bâtiment ; renvoie true si arrivée.
function goTo(u, dt, target, key) {
  u.repathTimer -= dt;
  if (u.pathTarget !== key || (!u.path.length && u.repathTimer <= 0)) {
    u.path = findPath(u.x, u.y, target, u.radius);
    u.pathTarget = key;
    u.repathTimer = 0.8;
    if (!u.path.length) return true;
  }
  return moveAlongPath(u, dt);
}

function updateUnit(u, dt) {
  u.cooldown = Math.max(0, u.cooldown - dt);
  u.attackAnim = Math.max(0, u.attackAnim - dt);
  const o = u.order;
  const isWorker = u.type === 'worker';

  // Acquisition automatique des cibles
  u.scanTimer -= dt;
  if (u.scanTimer <= 0) {
    u.scanTimer = 0.3;
    if (!isWorker && (!o || o.type === 'hold' || o.type === 'attackMove' || (o.type === 'attack' && !o.forced))) {
      const range = (o && o.type === 'hold') ? u.def.range : u.def.sight;
      const cur = o ? o.target : null;
      if (!cur || cur.dead || cur.kind === 'building') {
        const e = findEnemyNear(u, range);
        if (e && e !== cur && (!cur || cur.dead || e.kind === 'unit')) {
          if (!o || o.type === 'attack') {
            u.order = { type: 'attack', target: e, forced: false, homeX: u.x, homeY: u.y };
            u.path = []; u.pathTarget = null;
          } else if (o.type === 'attackMove') {
            o.target = e;
          } else if (o.type === 'hold') {
            o.target = e;
          }
        }
      }
    } else if (isWorker && !o) {
      // Un ouvrier inactif se défend s'il est au contact
      const e = findEnemyNear(u, 12);
      if (e && e.kind === 'unit') u.order = { type: 'attack', target: e, forced: false };
    }
  }

  if (!o) { unstickIfNeeded(u); return; }

  switch (o.type) {
    case 'move': {
      const arrived = goTo(u, dt, { x: o.x, y: o.y }, 'm' + o.x + ',' + o.y);
      if (arrived || Math.hypot(o.x - u.x, o.y - u.y) < 6) u.order = null;
      else checkStuck(u, dt, o.x, o.y);
      break;
    }
    case 'attackMove': {
      if (o.target && (o.target.dead || edgeDist(u, o.target) > u.def.sight + 60)) o.target = null;
      if (o.target) {
        attackTarget(u, dt, o.target);
      } else {
        const arrived = goTo(u, dt, { x: o.x, y: o.y }, 'am' + o.x + ',' + o.y);
        if (arrived || Math.hypot(o.x - u.x, o.y - u.y) < 8) u.order = null;
        else checkStuck(u, dt, o.x, o.y);
      }
      break;
    }
    case 'attack': {
      const t = o.target;
      if (!t || t.dead) { u.order = null; break; }
      if (t.kind === 'unit' && t.team !== PLAYER && u.team === PLAYER && !isVisibleToPlayer(t) && o.forced) {
        // Cible perdue dans le brouillard : aller à sa dernière position connue.
        u.order = { type: 'move', x: t.x, y: t.y };
        break;
      }
      // Les unités qui ripostent automatiquement ne poursuivent pas trop loin.
      if (!o.forced && o.homeX !== undefined && Math.hypot(u.x - o.homeX, u.y - o.homeY) > u.def.sight + 150) {
        u.order = { type: 'move', x: o.homeX, y: o.homeY };
        break;
      }
      attackTarget(u, dt, t);
      break;
    }
    case 'hold': {
      if (o.target && (o.target.dead || edgeDist(u, o.target) > u.def.range)) o.target = null;
      if (o.target) strike(u, o.target);
      break;
    }
    case 'harvest': updateHarvest(u, dt, o); break;
    case 'return': updateReturn(u, dt, o); break;
    case 'build': updateBuild(u, dt, o); break;
  }
}

function unstickIfNeeded(u) {
  if (!isWalkableWorld(u.x, u.y)) unstick(u);
}

function checkStuck(u, dt, x, y) {
  const d = Math.hypot(x - u.x, y - u.y);
  if (d < u.lastDist - 2) { u.lastDist = d; u.stuckTimer = 0; return; }
  u.stuckTimer += dt;
  if (u.stuckTimer > 1.5) {
    // Bloqué par d'autres unités : s'arrêter si on est proche, sinon recalculer.
    if (d < 60) u.order = null;
    else { u.path = []; u.pathTarget = null; u.stuckTimer = 0; u.lastDist = d; }
  }
}

function attackTarget(u, dt, t) {
  const d = edgeDist(u, t);
  const range = u.def.range;
  if (u.def.minRange && t.kind === 'unit' && d < u.def.minRange) {
    // Trop près pour une catapulte : reculer
    const a = Math.atan2(u.y - t.y, u.x - t.x);
    const nx = u.x + Math.cos(a) * u.def.speed * dt, ny = u.y + Math.sin(a) * u.def.speed * dt;
    if (isWalkableWorld(nx, ny)) { u.x = nx; u.y = ny; }
    return;
  }
  if (d <= range) {
    u.path = []; u.pathTarget = null;
    strike(u, t);
    return;
  }
  if (t.kind === 'unit') {
    const key = 'u' + t.id + ':' + Math.floor(t.x / 48) + ',' + Math.floor(t.y / 48);
    goTo(u, dt, { x: t.x, y: t.y }, key);
    if (!u.path.length) {
      // Contact direct
      const a = Math.atan2(t.y - u.y, t.x - u.x);
      const nx = u.x + Math.cos(a) * u.def.speed * dt, ny = u.y + Math.sin(a) * u.def.speed * dt;
      if (isWalkableWorld(nx, ny)) { u.x = nx; u.y = ny; }
    }
  } else {
    approachRect(u, dt, t, 'b' + t.id, range);
  }
}

// S'approche d'un bâtiment/mine ; renvoie true quand l'unité est au contact.
function approachRect(u, dt, e, key, dist) {
  if (edgeDist(u, e) <= dist) { u.path = []; return true; }
  goTo(u, dt, { rect: rectOf(e) }, key);
  if (!u.path.length) {
    // Fin du chemin : avancer directement vers le point le plus proche du rectangle
    const px = Math.max(e.tx * TILE, Math.min((e.tx + e.tw) * TILE, u.x));
    const py = Math.max(e.ty * TILE, Math.min((e.ty + e.th) * TILE, u.y));
    const a = Math.atan2(py - u.y, px - u.x);
    const nx = u.x + Math.cos(a) * u.def.speed * dt, ny = u.y + Math.sin(a) * u.def.speed * dt;
    if (isWalkableWorld(nx, ny)) { u.x = nx; u.y = ny; }
    else if (edgeDist(u, e) > dist + 24) { u.pathTarget = null; u.repathTimer = 0; }
  }
  return false;
}

function strike(u, t) {
  u.facing = Math.atan2(t.y - u.y, t.x - u.x);
  if (u.cooldown > 0) return;
  u.cooldown = u.def.cooldown;
  u.attackAnim = 0.2;
  if (u.def.projectile) {
    spawnProjectile(u, t);
  } else {
    dealDamage(u, t, u.def.dmg);
  }
}

function damageFor(attacker, target, base) {
  let dmg = base;
  const def = attacker.def;
  if (def.bonus && def.bonus[target.type]) dmg *= def.bonus[target.type];
  if (target.kind === 'building') {
    if (def.buildingBonus) dmg *= def.buildingBonus;
    else if (attacker.kind === 'unit' && attacker.def.projectile === 'arrow') dmg *= 0.4;
  }
  return Math.max(1, dmg - (target.def.armor || 0));
}

function dealDamage(attacker, target, base) {
  if (target.dead) return;
  const dmg = damageFor(attacker, target, base);
  target.hp -= dmg;
  target.lastHit = G.time;
  if (target.team === PLAYER && G.attackAlertTimer <= 0 && attacker.team === ENEMY) {
    G.attackAlertTimer = 12;
    notify(target.kind === 'building' ? 'Aux armes ! Nos terres sont attaquées !' : 'Nos troupes sont prises à partie !');
    G.lastAlert = { x: target.x, y: target.y };
  }
  // Riposte des unités inactives
  if (target.kind === 'unit' && !target.order && attacker.kind === 'unit' && target.type !== 'worker') {
    target.order = { type: 'attack', target: attacker, forced: false, homeX: target.x, homeY: target.y };
  }
  if (target.hp <= 0) kill(target, attacker);
}

function kill(e, killer) {
  if (e.dead) return;
  e.dead = true;
  e.hp = 0;
  if (killer && killer.team >= 0) G.teams[killer.team].stats[e.kind === 'unit' ? 'killed' : 'buildingsDestroyed']++;
  if (e.team >= 0) G.teams[e.team].stats[e.kind === 'unit' ? 'lost' : 'buildingsLost']++;
  if (e.kind === 'building') {
    setOccupancy(e, 0);
    G.effects.push({ type: 'rubble', x: e.x, y: e.y, w: e.tw * TILE, h: e.th * TILE, t: 0, life: 12 });
    G.effects.push({ type: 'explosion', x: e.x, y: e.y, r: e.radius * 1.4, t: 0, life: 0.8 });
  } else {
    G.effects.push({ type: 'death', x: e.x, y: e.y, team: e.team, r: e.radius, t: 0, life: 1.2 });
  }
}

function spawnProjectile(src, t) {
  const kind = src.def.projectile;
  const p = {
    kind, team: src.team, src, target: t,
    x: src.x, y: src.y, sx: src.x, sy: src.y,
    tx: t.x, ty: t.y, t: 0,
    dmg: src.def.dmg,
  };
  const d = Math.hypot(t.x - src.x, t.y - src.y);
  p.dur = kind === 'stone' ? Math.max(0.5, d / 260) : Math.max(0.15, d / 520);
  G.projectiles.push(p);
}

function updateProjectiles(dt) {
  for (const p of G.projectiles) {
    p.t += dt;
    if (p.kind === 'arrow' && !p.target.dead) { p.tx = p.target.x; p.ty = p.target.y; }
    const k = Math.min(1, p.t / p.dur);
    p.x = p.sx + (p.tx - p.sx) * k;
    p.y = p.sy + (p.ty - p.sy) * k;
    if (k >= 1) {
      p.done = true;
      if (p.kind === 'arrow') {
        if (!p.target.dead) dealDamage(p.src, p.target, p.dmg);
      } else {
        // Dégâts de zone
        const splash = p.src.def.splash || 30;
        G.effects.push({ type: 'explosion', x: p.tx, y: p.ty, r: splash, t: 0, life: 0.5 });
        for (const e of G.units) {
          if (e.dead || e.team === p.team) continue;
          const d = Math.hypot(e.x - p.tx, e.y - p.ty) - e.radius;
          if (d <= splash) dealDamage(p.src, e, p.dmg * (d <= splash / 3 ? 1 : 0.5));
        }
        for (const b of G.buildings) {
          if (b.dead || b.team === p.team) continue;
          if (edgeDist({ x: p.tx, y: p.ty, radius: 0 }, b) <= 4) dealDamage(p.src, b, p.dmg);
        }
      }
    }
  }
  G.projectiles = G.projectiles.filter(p => !p.done);
}

// Séparation douce entre unités pour éviter qu'elles se superposent.
function separateUnits(dt) {
  const cell = 48;
  const grid = new Map();
  for (const u of G.units) {
    const k = Math.floor(u.x / cell) + Math.floor(u.y / cell) * 1000;
    let arr = grid.get(k);
    if (!arr) grid.set(k, arr = []);
    arr.push(u);
  }
  for (const u of G.units) {
    const cx = Math.floor(u.x / cell), cy = Math.floor(u.y / cell);
    let px = 0, py = 0;
    for (let oy = -1; oy <= 1; oy++) {
      for (let ox = -1; ox <= 1; ox++) {
        const arr = grid.get(cx + ox + (cy + oy) * 1000);
        if (!arr) continue;
        for (const v of arr) {
          if (v === u) continue;
          const dx = u.x - v.x, dy = u.y - v.y;
          const min = u.radius + v.radius - 2;
          const d2 = dx * dx + dy * dy;
          if (d2 >= min * min) continue;
          const d = Math.sqrt(d2) || 0.01;
          const push = (min - d) / min;
          // Les ouvriers qui récoltent se traversent pour ne pas bloquer la mine.
          if (u.type === 'worker' && v.type === 'worker' && u.order && v.order) continue;
          const weight = (u.order && u.order.type === 'hold') ? 0.1 : (v.path.length && !u.path.length ? 1.2 : 0.8);
          px += (dx / d || Math.random() - 0.5) * push * weight;
          py += (dy / d || Math.random() - 0.5) * push * weight;
        }
      }
    }
    if (px || py) {
      const s = 90 * dt;
      const nx = u.x + px * s, ny = u.y + py * s;
      if (isWalkableWorld(nx, u.y)) u.x = nx;
      if (isWalkableWorld(u.x, ny)) u.y = ny;
    }
    u.x = Math.max(4, Math.min(WORLD_W - 4, u.x));
    u.y = Math.max(4, Math.min(WORLD_H - 4, u.y));
  }
}

// Récolte ----------------------------------------------------------------------

function nearestDropoff(u) {
  let best = null, bestD = Infinity;
  for (const b of G.buildings) {
    if (b.team !== u.team || !b.complete || !b.def.dropoff) continue;
    const d = Math.hypot(b.x - u.x, b.y - u.y);
    if (d < bestD) { bestD = d; best = b; }
  }
  return best;
}

function nearestMine(x, y, exclude) {
  let best = null, bestD = Infinity;
  for (const m of G.mines) {
    if (m.dead || m.gold <= 0 || m === exclude) continue;
    const d = Math.hypot(m.x - x, m.y - y);
    if (d < bestD) { bestD = d; best = m; }
  }
  return best;
}

function updateHarvest(u, dt, o) {
  let m = o.mine;
  if (!m || m.dead || m.gold <= 0) {
    m = nearestMine(u.x, u.y);
    if (!m || Math.hypot(m.x - u.x, m.y - u.y) > 900) {
      if (u.carry > 0) { u.order = { type: 'return', mine: null }; } else u.order = null;
      return;
    }
    o.mine = m; u.lastMine = m;
  }
  if (u.carry >= GATHER_AMOUNT) { u.order = { type: 'return', mine: m }; u.path = []; u.pathTarget = null; return; }
  if (!approachRect(u, dt, m, 'mine' + m.id, 10)) return;
  u.facing = Math.atan2(m.y - u.y, m.x - u.x);
  u.gatherTimer += dt * G.teams[u.team].gatherMult;
  u.attackAnim = (u.gatherTimer % 0.6) < 0.15 ? 0.1 : 0;
  if (u.gatherTimer >= GATHER_TIME) {
    u.gatherTimer = 0;
    const amt = Math.min(GATHER_AMOUNT, m.gold);
    m.gold -= amt;
    u.carry = amt;
    if (m.gold <= 0) {
      m.dead = true;
      setOccupancy(m, 0);
      notify("Une mine d'or est épuisée", u.team);
    }
    u.order = { type: 'return', mine: m };
    u.path = []; u.pathTarget = null;
  }
}

function updateReturn(u, dt, o) {
  const d = nearestDropoff(u);
  if (!d) { u.order = null; return; }
  if (!approachRect(u, dt, d, 'drop' + d.id, 10)) return;
  G.teams[u.team].gold += u.carry;
  G.teams[u.team].stats.gathered += u.carry;
  u.carry = 0;
  const m = (o.mine && !o.mine.dead && o.mine.gold > 0) ? o.mine : nearestMine(u.x, u.y);
  if (m) { u.order = { type: 'harvest', mine: m }; u.path = []; u.pathTarget = null; }
  else u.order = null;
}

// Construction ----------------------------------------------------------------

function updateBuild(u, dt, o) {
  const b = o.building;
  if (!b || b.dead || b.complete) {
    u.order = null;
    // Enchaîner sur le chantier voisin (ex. une ligne de murailles), sinon retourner récolter
    let next = null, nextD = 320;
    for (const o2 of G.buildings) {
      if (o2.team !== u.team || o2.complete || o2.dead) continue;
      const d = Math.hypot(o2.x - u.x, o2.y - u.y);
      if (d < nextD) { nextD = d; next = o2; }
    }
    if (next) u.order = { type: 'build', building: next };
    else if (b && b.complete && u.lastMine && !u.lastMine.dead) u.order = { type: 'harvest', mine: u.lastMine };
    return;
  }
  if (!approachRect(u, dt, b, 'build' + b.id, 10)) return;
  u.facing = Math.atan2(b.y - u.y, b.x - u.x);
  u.attackAnim = (G.time % 0.5) < 0.12 ? 0.1 : 0;
  const inc = dt / b.def.time;
  b.progress = Math.min(1, b.progress + inc);
  b.hp = Math.min(b.maxHp, b.hp + b.maxHp * 0.9 * inc);
  if (b.progress >= 1) {
    b.complete = true;
    notify(`Construction achevée : ${b.def.name}`, b.team);
  }
}

// Bâtiments -------------------------------------------------------------------

function updateBuilding(b, dt) {
  if (!b.complete) return;
  // Tours de défense
  if (b.def.dmg) {
    b.cooldown = Math.max(0, b.cooldown - dt);
    b.scanTimer -= dt;
    if (!b.target || b.target.dead || edgeDist(b.target, b) > b.def.range) {
      b.target = null;
      if (b.scanTimer <= 0) {
        b.scanTimer = 0.3;
        let best = null, bestD = Infinity;
        for (const e of G.units) {
          if (e.team === b.team || e.dead) continue;
          const d = edgeDist(e, b);
          if (d <= b.def.range && d < bestD) { bestD = d; best = e; }
        }
        b.target = best;
      }
    }
    if (b.target && b.cooldown <= 0) {
      b.cooldown = b.def.cooldown;
      spawnProjectile(b, b.target);
    }
  }
  // Production
  if (!b.queue.length) return;
  const item = b.queue[0];
  const def = UNIT_TYPES[item.type];
  if (!item.started) {
    const pop = teamPop(b.team);
    if (pop.used + def.pop > pop.cap) {
      if (!b.popWarned) { notify('Plus de place pour loger vos sujets : bâtissez des chaumières', b.team); b.popWarned = true; }
      return;
    }
    b.popWarned = false;
    item.started = true;
  }
  item.t += dt;
  if (item.t >= def.time) {
    b.queue.shift();
    spawnFromBuilding(b, item.type);
  }
}

function spawnFromBuilding(b, type) {
  // Trouver une case libre autour du bâtiment, du côté du point de ralliement
  const rx = b.rally ? b.rally.x : b.x + (b.team === PLAYER ? 1 : -1) * 200;
  const ry = b.rally ? b.rally.y : b.y + (b.team === PLAYER ? -1 : 1) * 100;
  let best = null, bestD = Infinity;
  for (let y = b.ty - 1; y <= b.ty + b.th; y++) {
    for (let x = b.tx - 1; x <= b.tx + b.tw; x++) {
      if (!isWalkable(x, y)) continue;
      const px = x * TILE + TILE / 2, py = y * TILE + TILE / 2;
      const d = Math.hypot(px - rx, py - ry);
      if (d < bestD) { bestD = d; best = { x: px, y: py }; }
    }
  }
  if (!best) {
    const n = nearestWalkableTile(b.tx, b.ty, 10);
    if (!n) return;
    best = { x: n.x * TILE + TILE / 2, y: n.y * TILE + TILE / 2 };
  }
  const u = addUnit(type, b.team, best.x, best.y);
  G.teams[b.team].stats.trained++;
  if (b.rally) {
    if (b.rally.mine && type === 'worker') issueOrder(u, { type: 'harvest', mine: b.rally.mine });
    else issueOrder(u, { type: 'move', x: b.rally.x, y: b.rally.y });
  } else if (type === 'worker') {
    const m = nearestMine(u.x, u.y);
    if (m && Math.hypot(m.x - u.x, m.y - u.y) < 500) issueOrder(u, { type: 'harvest', mine: m });
  }
  return u;
}

// Brouillard de guerre -------------------------------------------------------

function updateFog() {
  const vis = G.visible;
  vis.fill(0);
  const reveal = (x, y, sight) => {
    const r = Math.ceil(sight / TILE);
    const cx = Math.floor(x / TILE), cy = Math.floor(y / TILE);
    const r2 = (sight / TILE) * (sight / TILE);
    for (let ty = Math.max(0, cy - r); ty <= Math.min(MAP_H - 1, cy + r); ty++) {
      for (let tx = Math.max(0, cx - r); tx <= Math.min(MAP_W - 1, cx + r); tx++) {
        const dx = tx - cx, dy = ty - cy;
        if (dx * dx + dy * dy <= r2) {
          const i = tileIdx(tx, ty);
          vis[i] = 1;
          G.explored[i] = 1;
        }
      }
    }
  };
  for (const u of G.units) if (u.team === PLAYER) reveal(u.x, u.y, u.def.sight);
  for (const b of G.buildings) if (b.team === PLAYER) reveal(b.x, b.y, b.complete ? b.def.sight : 120);
  for (const b of G.buildings) if (b.team !== PLAYER && !b.seen && isVisibleToPlayer(b)) b.seen = true;
}
