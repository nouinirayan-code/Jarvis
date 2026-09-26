'use strict';

// ---------------------------------------------------------------------------
// Intelligence artificielle de l'adversaire
// ---------------------------------------------------------------------------

const AI = {
  timer: 0,
  waveSize: 0,
  attacking: false,
  attackTarget: null,
  lastDefend: 0,
};

function aiReset() {
  AI.timer = 0;
  AI.waveSize = G.diff.waveBase;
  AI.attacking = false;
  AI.attackTarget = null;
  AI.lastDefend = 0;
}

function aiUpdate(dt) {
  AI.timer -= dt;
  if (AI.timer > 0) return;
  AI.timer = 0.75;

  const team = ENEMY;
  const t = G.teams[team];
  const mine = G.buildings.filter(b => b.team === team);
  const hq = mine.find(b => b.type === 'hq' && b.complete);
  const units = G.units.filter(u => u.team === team);
  const workers = units.filter(u => u.type === 'worker');
  const army = units.filter(u => u.type !== 'worker');
  const pop = teamPop(team);
  const count = type => mine.filter(b => b.type === type).length;
  const center = hq || mine[0];
  if (!center) return;

  // 1. Ouvriers : chantiers d'abord, puis récolte
  for (const b of mine) {
    if (b.complete) continue;
    const builders = workers.filter(w => w.order && w.order.type === 'build' && w.order.building === b);
    if (!builders.length) {
      const w = closest(workers.filter(w => !w.order || w.order.type === 'harvest'), b);
      if (w) issueOrder(w, { type: 'build', building: b });
    }
  }
  for (const w of workers) {
    if (!w.order) {
      const m = nearestMine(center.x, center.y) || nearestMine(w.x, w.y);
      if (m) issueOrder(w, { type: 'harvest', mine: m });
    }
  }
  // Répartir les ouvriers entre les mines proches
  balanceMines(workers, center);

  // 2. Former des ouvriers
  if (hq && workers.length < G.diff.maxWorkers && hq.queue.length === 0 && t.gold >= 50 && pop.used < pop.cap) {
    queueTraining(hq, 'worker');
  }

  const building = type => mine.some(b => b.type === type && !b.complete);

  // 3. Maisons
  if (pop.cap < MAX_POP && pop.cap - pop.used <= 4 && !building('house') && t.gold >= BUILDING_TYPES.house.cost) {
    aiBuild('house', center, workers);
  }

  // 4. Ordre de construction
  const time = G.time;
  const wantBarracks = workers.length >= 6 ? (time > 300 || t.gold > 500 ? 2 : 1) : 0;
  if (count('barracks') < wantBarracks && !building('barracks') && t.gold >= 150) aiBuild('barracks', center, workers);
  else if (time > 140 && count('stable') < 1 && hasBuilding(team, 'barracks', true) && t.gold >= 200) aiBuild('stable', center, workers);
  else if (time > 240 && count('workshop') < 1 && hasBuilding(team, 'barracks', true) && t.gold >= 250) aiBuild('workshop', center, workers);
  else if (time > 120 && count('tower') < Math.min(3, 1 + Math.floor(time / 300)) && !building('tower') && t.gold >= 200) {
    aiBuild('tower', center, workers, true);
  }

  // 5. Former l'armée
  const playerUnits = G.units.filter(u => u.team === PLAYER);
  const pKnights = playerUnits.filter(u => u.type === 'knight').length;
  const pArchers = playerUnits.filter(u => u.type === 'archer').length;
  const pSpear = playerUnits.filter(u => u.type === 'spearman').length;
  const reserve = building('house') ? 0 : 60;
  let armyPop = army.reduce((s, u) => s + u.def.pop, 0);
  for (const b of mine) {
    if (armyPop >= G.diff.maxArmyPop || Math.random() > G.diff.trainChance) continue;
    if (!b.complete || !b.def.trains || b.type === 'hq' || b.queue.length >= (t.gold > 400 ? 3 : 2)) continue;
    let type;
    if (b.type === 'barracks') {
      const spearBias = 0.5 + (pKnights - pArchers) * 0.05;
      type = Math.random() < Math.max(0.25, Math.min(0.8, spearBias)) ? 'spearman' : 'archer';
    } else {
      type = b.def.trains[0];
    }
    if (type === 'knight' && pSpear > pArchers * 2 && Math.random() < 0.5) continue;
    if (t.gold - reserve >= UNIT_TYPES[type].cost && pop.used + UNIT_TYPES[type].pop <= pop.cap) {
      if (queueTraining(b, type)) armyPop += UNIT_TYPES[type].pop;
    }
  }

  // 6. Défense de la base
  const threats = G.units.filter(u => u.team === PLAYER && mine.some(b => Math.hypot(b.x - u.x, b.y - u.y) < 500));
  if (threats.length) {
    const tx = threats[0].x, ty = threats[0].y;
    const defenders = army.filter(u => !u.order || u.order.type !== 'attack' || !u.order.target || u.order.target.dead);
    if (G.time - AI.lastDefend > 3 && defenders.length) {
      AI.lastDefend = G.time;
      commandMove(defenders.filter(u => !AI.attacking || Math.hypot(u.x - center.x, u.y - center.y) < 900), tx, ty, true);
    }
    // Les ouvriers menacés directement se défendent en dernier recours
    if (army.length === 0 && threats.length <= 3) {
      for (const w of workers) {
        const e = closest(threats, w);
        if (e && Math.hypot(e.x - w.x, e.y - w.y) < 150) issueOrder(w, { type: 'attack', target: e, forced: true });
      }
    }
    return;
  }

  // 7. Vagues d'attaque
  const idleArmy = army.filter(u => !u.order);
  if (!AI.attacking) {
    // Regroupement devant la base
    const rx = center.x - 220, ry = center.y + 220;
    for (const u of idleArmy) {
      if (Math.hypot(u.x - rx, u.y - ry) > 160) issueOrder(u, { type: 'attackMove', x: rx + (Math.random() - 0.5) * 120, y: ry + (Math.random() - 0.5) * 120 });
    }
    if (G.time >= G.diff.firstWave && armyPop >= AI.waveSize) {
      AI.attacking = true;
      AI.waveSize += G.diff.waveGrow;
      launchAttack(army);
    }
  } else {
    if (army.length < 3) { AI.attacking = false; return; }
    // Relancer les unités arrivées ou inactives vers la prochaine cible
    if (idleArmy.length) launchAttack(idleArmy);
  }
}

function launchAttack(units) {
  const targets = G.buildings.filter(b => b.team === PLAYER && b.type !== 'wall');
  if (!targets.length) return;
  let cx = 0, cy = 0;
  for (const u of units) { cx += u.x; cy += u.y; }
  cx /= units.length; cy /= units.length;
  // Viser d'abord les bâtiments les plus proches de l'armée
  const target = closest(targets, { x: cx, y: cy });
  AI.attackTarget = target;
  commandMove(units, target.x, target.y, true);
}

function balanceMines(workers, center) {
  const nearby = G.mines.filter(m => !m.dead && m.gold > 0 && Math.hypot(m.x - center.x, m.y - center.y) < 450);
  if (nearby.length < 2) return;
  const counts = new Map(nearby.map(m => [m, 0]));
  for (const w of workers) {
    const m = w.order && (w.order.type === 'harvest' || w.order.type === 'return') ? w.order.mine : null;
    if (m && counts.has(m)) counts.set(m, counts.get(m) + 1);
  }
  const sorted = [...counts.entries()].sort((a, b) => a[1] - b[1]);
  const [low, lowN] = sorted[0];
  const [high, highN] = sorted[sorted.length - 1];
  if (highN - lowN >= 2) {
    const w = workers.find(w => w.order && w.order.type === 'harvest' && w.order.mine === high && w.carry === 0);
    if (w) issueOrder(w, { type: 'harvest', mine: low });
  }
}

function closest(list, p) {
  let best = null, bestD = Infinity;
  for (const e of list) {
    const d = Math.hypot(e.x - p.x, e.y - p.y);
    if (d < bestD) { bestD = d; best = e; }
  }
  return best;
}

function aiBuild(type, center, workers, forward) {
  const def = BUILDING_TYPES[type];
  const spot = findBuildSpot(type, center, forward);
  if (!spot) return;
  const available = workers.filter(w => !w.order || w.order.type === 'harvest');
  const w = closest(available, { x: spot.tx * TILE, y: spot.ty * TILE });
  if (!w) return;
  if (G.teams[ENEMY].gold < def.cost) return;
  tryPlaceBuilding(ENEMY, type, spot.tx, spot.ty, [w]);
}

function findBuildSpot(type, center, forward) {
  const def = BUILDING_TYPES[type];
  const cx = Math.floor(center.x / TILE), cy = Math.floor(center.y / TILE);
  // Les tours sont placées du côté de l'adversaire
  const bias = forward ? { x: -4, y: 4 } : { x: 0, y: 0 };
  const candidates = [];
  for (let r = 3; r <= 13; r++) {
    for (let y = cy - r; y <= cy + r; y++) {
      for (let x = cx - r; x <= cx + r; x++) {
        if (Math.max(Math.abs(x - cx), Math.abs(y - cy)) !== r) continue;
        const tx = x + bias.x, ty = y + bias.y;
        if (!spotFree(tx - 1, ty - 1, def.w + 2, def.h + 2)) continue;
        if (!canPlaceBuilding(type, tx, ty, ENEMY)) continue;
        candidates.push({ tx, ty });
      }
    }
    if (candidates.length) return candidates[Math.floor(Math.random() * candidates.length)];
  }
  return null;
}

// Vérifie qu'une zone (avec marge) est libre pour garder des couloirs de passage.
function spotFree(tx, ty, w, h) {
  for (let y = ty; y < ty + h; y++) {
    for (let x = tx; x < tx + w; x++) {
      if (!inMap(x, y)) return false;
      const i = tileIdx(x, y);
      if (G.terrain[i] !== T_GRASS || G.occ[i] !== 0) return false;
    }
  }
  return true;
}
