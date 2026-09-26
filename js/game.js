'use strict';

// ---------------------------------------------------------------------------
// État du jeu et simulation
// ---------------------------------------------------------------------------

let G = null;

function newGame(seed) {
  seed = seed || (Math.random() * 1e9) | 0;
  const world = generateWorld(seed);
  G = {
    seed,
    time: 0,
    phase: 'day', phaseT: 0, night: 0,
    terrain: world.terrain,
    grid: new Int32Array(MAP_W * MAP_H),
    ents: new Map(),
    nextId: 1,
    nodes: [], depleted: [], buildings: [], enemies: [], projectiles: [], pickups: [],
    particles: [], floaters: [], messages: [],
    res: { wood: 10, stone: 4, ember: 0 },
    upgrades: { blade: 0, heart: 0, lantern: 0, swift: 0, hearth: 0 },
    stats: { kills: 0, built: 0, embers: 0, nightsSurvived: 0 },
    spawnLeft: 0, spawnTimer: 0, bossPending: false,
    flow: null, flowDirty: true,
    over: null, paused: false,
    lights: [],
  };

  const h = {
    id: G.nextId++, kind: 'hearth', solid: true,
    tx: HEARTH_TX, ty: HEARTH_TY, tw: 2, th: 2, x: HEARTH_X, y: HEARTH_Y, radius: TILE,
    hp: HEARTH.hp, maxHp: HEARTH.hp, fuel: HEARTH.fuel, hitFlash: 0,
  };
  G.hearth = h;
  G.ents.set(h.id, h);
  for (let y = h.ty; y < h.ty + 2; y++) for (let x = h.tx; x < h.tx + 2; x++) G.grid[idx(x, y)] = h.id;

  for (const n of world.nodes) addNode(n.type, n.tx, n.ty);

  G.player = {
    x: HEARTH_X, y: HEARTH_Y + 80, radius: PLAYER_DEF.radius,
    hp: PLAYER_DEF.hp, maxHp: PLAYER_DEF.hp,
    oil: PLAYER_DEF.oil, maxOil: PLAYER_DEF.oil,
    facing: -Math.PI / 2, attackCd: 0, swingT: 0,
    dashT: 0, dashCd: 0, dashDx: 0, dashDy: 0,
    invuln: 0, hitFlash: 0, downT: 0, walkT: 0,
  };
  computeFlowField();
  message('Le dernier foyer brûle encore. Rassemblez du bois et de la pierre avant la nuit.');
  return G;
}

// Entités ---------------------------------------------------------------------

function addNode(type, tx, ty) {
  const def = NODE_TYPES[type];
  const n = {
    id: G.nextId++, kind: 'node', type, def, solid: true,
    tx, ty, x: tx * TILE + TILE / 2, y: ty * TILE + TILE / 2, radius: def.radius,
    amount: def.amount, shake: 0, variant: Math.random(),
  };
  G.nodes.push(n);
  G.ents.set(n.id, n);
  G.grid[idx(tx, ty)] = n.id;
  return n;
}

function removeEntityFromGrid(e) {
  if (G.grid[idx(e.tx, e.ty)] === e.id) G.grid[idx(e.tx, e.ty)] = 0;
  G.ents.delete(e.id);
}

function addBuilding(type, tx, ty) {
  const def = BUILD_TYPES[type];
  const b = {
    id: G.nextId++, kind: 'building', type, def, solid: def.solid,
    tx, ty, x: tx * TILE + TILE / 2, y: ty * TILE + TILE / 2, radius: TILE / 2,
    hp: def.hp, maxHp: def.hp, cd: 0, hitFlash: 0, aim: -Math.PI / 2, built: 0,
  };
  G.buildings.push(b);
  G.ents.set(b.id, b);
  G.grid[idx(tx, ty)] = b.id;
  G.flowDirty = true;
  G.stats.built++;
  return b;
}

function destroyBuilding(b) {
  if (b.dead) return;
  b.dead = true;
  removeEntityFromGrid(b);
  G.flowDirty = true;
  burst(b.x, b.y, '#a16207', 14, 140);
}

function message(text) {
  G.messages.push({ text, t: 4 });
  if (G.messages.length > 3) G.messages.shift();
}

function floater(x, y, text, color) {
  G.floaters.push({ x, y, text, color: color || '#fde68a', t: 0 });
}

function burst(x, y, color, n, speed, life) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, s = Math.random() * speed;
    G.particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, t: 0, life: (life || 0.6) * (0.5 + Math.random() * 0.8), color, size: 2 + Math.random() * 3 });
  }
}

// Lumière ---------------------------------------------------------------------

function hearthRadius() {
  return HEARTH.baseRadius + G.hearth.fuel * HEARTH.radiusPerFuel;
}

// Sources de lumière qui affaiblissent les ombres (le foyer, les torches, les phares)
function refreshLights() {
  const L = [{ x: HEARTH_X, y: HEARTH_Y, r: hearthRadius(), kind: 'hearth' }];
  for (const b of G.buildings) if (!b.dead && b.def.light) L.push({ x: b.x, y: b.y, r: b.def.light, kind: b.type });
  G.lights = L;
}

function lightAt(x, y) {
  for (const l of G.lights) {
    const dx = x - l.x, dy = y - l.y;
    if (dx * dx + dy * dy <= l.r * l.r) return true;
  }
  return false;
}

function playerLanternRadius() {
  return PLAYER_DEF.lantern * (1 + 0.2 * G.upgrades.lantern) * (G.player.oil > 0 ? 1 : 0.45);
}

// Ressources ------------------------------------------------------------------

function canAfford(cost) {
  return Object.entries(cost).every(([k, v]) => G.res[k] >= v);
}
function pay(cost) { for (const [k, v] of Object.entries(cost)) G.res[k] -= v; }
function costText(cost) {
  const names = { wood: 'bois', stone: 'pierre', ember: 'braise' };
  return Object.entries(cost).map(([k, v]) => `${v} ${names[k]}${v > 1 && k !== 'wood' ? 's' : ''}`).join(', ');
}

function canBuildAt(type, tx, ty) {
  if (!inMap(tx, ty)) return false;
  const i = idx(tx, ty);
  if (G.terrain[i] !== T_GRASS || G.grid[i]) return false;
  const x = tx * TILE + TILE / 2, y = ty * TILE + TILE / 2;
  // On ne bâtit que dans la lumière (foyer, torches, phares)
  if (!lightAt(x, y)) return false;
  const def = BUILD_TYPES[type];
  if (def.solid) {
    const p = G.player;
    const px = Math.max(tx * TILE, Math.min(p.x, (tx + 1) * TILE)), py = Math.max(ty * TILE, Math.min(p.y, (ty + 1) * TILE));
    if (Math.hypot(px - p.x, py - p.y) < p.radius) return false;
    for (const e of G.enemies) if (Math.hypot(e.x - x, e.y - y) < e.radius + TILE / 2) return false;
  }
  return true;
}

function tryBuild(type, tx, ty) {
  const def = BUILD_TYPES[type];
  if (!canAfford(def.cost)) { message(`Il faut ${costText(def.cost)}.`); return false; }
  if (!canBuildAt(type, tx, ty)) { message('Impossible de bâtir ici : il faut un emplacement libre et éclairé.'); return false; }
  pay(def.cost);
  const b = addBuilding(type, tx, ty);
  burst(b.x, b.y, '#d6b77a', 10, 80);
  return true;
}

function repairAt(x, y) {
  const b = G.buildings.find(o => !o.dead && Math.hypot(o.x - x, o.y - y) < TILE * 0.7);
  if (!b || b.hp >= b.maxHp) return false;
  if (Math.hypot(b.x - G.player.x, b.y - G.player.y) > 140) { message('Approchez-vous pour réparer.'); return false; }
  if (G.res.wood < 1) { message('Il faut 1 bois pour réparer.'); return false; }
  G.res.wood--;
  b.hp = Math.min(b.maxHp, b.hp + b.maxHp * 0.35);
  floater(b.x, b.y - 20, 'Réparé', '#86efac');
  return true;
}

function demolishAt(x, y) {
  const b = G.buildings.find(o => !o.dead && Math.hypot(o.x - x, o.y - y) < TILE * 0.7);
  if (!b) return false;
  for (const [k, v] of Object.entries(b.def.cost)) G.res[k] += Math.floor(v / 2);
  destroyBuilding(b);
  message(`${b.def.name} démontée (moitié des matériaux récupérée).`);
  return true;
}

function feedHearth() {
  const p = G.player, h = G.hearth;
  if (Math.hypot(p.x - h.x, p.y - h.y) > 120) { message('Approchez-vous du foyer pour le nourrir.'); return; }
  if (h.fuel >= HEARTH.maxFuel - 0.5) { message('La flamme est déjà à son maximum.'); return; }
  if (G.res.ember > 0) {
    G.res.ember--;
    h.fuel = Math.min(HEARTH.maxFuel, h.fuel + HEARTH.emberFuel);
    floater(h.x, h.y - 50, `+${HEARTH.emberFuel} flamme`, '#fb923c');
  } else if (G.res.wood > 0) {
    const n = Math.min(5, G.res.wood);
    G.res.wood -= n;
    h.fuel = Math.min(HEARTH.maxFuel, h.fuel + n * HEARTH.woodFuel);
    floater(h.x, h.y - 50, `+${n * HEARTH.woodFuel} flamme`, '#fb923c');
  } else {
    message('Vous n\'avez ni braise ni bois à brûler.');
    return;
  }
  burst(h.x, h.y - 10, '#fb923c', 16, 120, 0.8);
}

function upgradeCost(key) { const u = UPGRADES[key]; return u.base + u.step * G.upgrades[key]; }

function buyUpgrade(key) {
  const u = UPGRADES[key];
  if (G.upgrades[key] >= u.max) return false;
  const cost = upgradeCost(key);
  if (G.res.ember < cost) { message(`Il faut ${cost} braises.`); return false; }
  G.res.ember -= cost;
  G.upgrades[key]++;
  const p = G.player;
  if (key === 'heart') { p.maxHp = PLAYER_DEF.hp + 25 * G.upgrades.heart; p.hp = p.maxHp; }
  if (key === 'lantern') { p.maxOil = PLAYER_DEF.oil * (1 + 0.2 * G.upgrades.lantern); p.oil = p.maxOil; }
  if (key === 'hearth') { G.hearth.maxHp = HEARTH.hp + 150 * G.upgrades.hearth; G.hearth.hp = Math.min(G.hearth.maxHp, G.hearth.hp + 150); }
  message(`${u.name} — niveau ${G.upgrades[key]} !`);
  burst(p.x, p.y, '#facc15', 20, 150);
  return true;
}

// Boucle -------------------------------------------------------------------------

function nightLength() { return NIGHT_BASE + (G.night - 1) * NIGHT_GROW; }

function darkness() {
  const t = G.phaseT;
  switch (G.phase) {
    case 'day': return 0.12;
    case 'dusk': return 0.12 + (t / DUSK_LENGTH) * 0.8;
    case 'night': return 0.92;
    case 'dawn': return 0.92 - (t / 4) * 0.8;
  }
  return 0.5;
}

function phaseRemaining() {
  if (G.phase === 'day') return DAY_LENGTH - G.phaseT + DUSK_LENGTH;
  if (G.phase === 'dusk') return DUSK_LENGTH - G.phaseT;
  if (G.phase === 'night') return nightLength() - G.phaseT;
  return 4 - G.phaseT;
}

function update(dt) {
  if (G.over || G.paused) return;
  G.time += dt;
  G.phaseT += dt;
  updatePhase();
  if (G.flowDirty) computeFlowField();
  refreshLights();

  updatePlayer(dt);
  updateHearth(dt);
  spawnEnemies(dt);
  for (const e of G.enemies) if (!e.dead) updateEnemy(e, dt);
  separateEnemies();
  for (const b of G.buildings) if (!b.dead) updateBuilding(b, dt);
  updateProjectiles(dt);
  updatePickups(dt);

  for (const n of G.nodes) n.shake = Math.max(0, n.shake - dt);
  for (const p of G.particles) { p.t += dt; p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.92; p.vy *= 0.92; }
  G.particles = G.particles.filter(p => p.t < p.life);
  for (const f of G.floaters) f.t += dt;
  G.floaters = G.floaters.filter(f => f.t < 1.2);
  for (const m of G.messages) m.t -= dt;
  G.messages = G.messages.filter(m => m.t > 0);

  G.enemies = G.enemies.filter(e => !e.dead);
  G.buildings = G.buildings.filter(b => !b.dead);
  G.nodes = G.nodes.filter(n => !n.dead);

  if (G.hearth.fuel <= 0) endGame('La flamme s\'est éteinte… Les ténèbres ont tout englouti.');
  else if (G.hearth.hp <= 0) endGame('Le foyer a été détruit par les ombres.');
}

function endGame(reason) {
  G.over = { reason };
}

function updatePhase() {
  if (G.phase === 'day' && G.phaseT >= DAY_LENGTH) {
    G.phase = 'dusk'; G.phaseT = 0;
    message('Le soleil décline… Rentrez près du foyer !');
  } else if (G.phase === 'dusk' && G.phaseT >= DUSK_LENGTH) {
    G.phase = 'night'; G.phaseT = 0; G.night++;
    G.spawnLeft = 4 + G.night * 3;
    G.spawnTimer = 1;
    G.bossPending = G.night % BOSS_EVERY === 0;
    message(G.bossPending ? `Nuit ${G.night} : la terre tremble… le Dévoreur approche !` : `Nuit ${G.night} : les ombres arrivent.`);
  } else if (G.phase === 'night' && G.phaseT >= nightLength()) {
    G.phase = 'dawn'; G.phaseT = 0;
    G.stats.nightsSurvived = G.night;
    for (const e of G.enemies) { e.dead = true; burst(e.x, e.y, '#fb923c', 10, 90, 0.9); }
    const reward = 1 + Math.floor(G.night / 2);
    G.res.ember += reward;
    message(`L'aube se lève : les ombres brûlent ! Le foyer vous offre ${reward} braise${reward > 1 ? 's' : ''}.`);
    regrowNodes();
  } else if (G.phase === 'dawn' && G.phaseT >= 4) {
    G.phase = 'day'; G.phaseT = 0;
  }
}

function regrowNodes() {
  const keep = [];
  for (const d of G.depleted) {
    const i = idx(d.tx, d.ty);
    const far = Math.hypot(d.tx * TILE - G.player.x, d.ty * TILE - G.player.y) > 120;
    if (Math.random() < 0.45 && !G.grid[i] && far) addNode(d.type, d.tx, d.ty);
    else keep.push(d);
  }
  G.depleted = keep;
  G.flowDirty = true;
}

// Héros --------------------------------------------------------------------------

function playerSpeed() { return PLAYER_DEF.speed * (1 + 0.08 * G.upgrades.swift); }

function updatePlayer(dt) {
  const p = G.player;
  p.attackCd = Math.max(0, p.attackCd - dt);
  p.swingT = Math.max(0, p.swingT - dt);
  p.dashCd = Math.max(0, p.dashCd - dt);
  p.invuln = Math.max(0, p.invuln - dt);
  p.hitFlash = Math.max(0, p.hitFlash - dt);

  if (p.downT > 0) {
    // Le héros est tombé : la flamme le ranime au foyer
    p.downT -= dt;
    if (p.downT <= 0) {
      p.x = HEARTH_X; p.y = HEARTH_Y + 70;
      p.hp = p.maxHp * 0.6; p.oil = p.maxOil; p.invuln = 2;
      message('La flamme vous ramène à la vie.');
    }
    return;
  }

  const inp = INPUT;
  let mx = (inp.right ? 1 : 0) - (inp.left ? 1 : 0);
  let my = (inp.down ? 1 : 0) - (inp.up ? 1 : 0);
  const len = Math.hypot(mx, my);
  if (len) { mx /= len; my /= len; }
  p.facing = Math.atan2(inp.mouseY - p.y, inp.mouseX - p.x);

  if (p.dashT > 0) {
    p.dashT -= dt;
    moveCircle(p, p.dashDx * PLAYER_DEF.dashSpeed * dt, p.dashDy * PLAYER_DEF.dashSpeed * dt);
    if (Math.random() < 0.8) G.particles.push({ x: p.x, y: p.y, vx: 0, vy: 0, t: 0, life: 0.3, color: '#fde68a', size: 4 });
  } else {
    moveCircle(p, mx * playerSpeed() * dt, my * playerSpeed() * dt);
    if (len) p.walkT += dt;
  }

  if (inp.dash && p.dashCd <= 0 && p.dashT <= 0) {
    const dx = len ? mx : Math.cos(p.facing), dy = len ? my : Math.sin(p.facing);
    p.dashDx = dx; p.dashDy = dy;
    p.dashT = PLAYER_DEF.dashTime;
    p.dashCd = PLAYER_DEF.dashCooldown * (1 - 0.1 * G.upgrades.swift);
    p.invuln = Math.max(p.invuln, PLAYER_DEF.dashTime + 0.08);
  }
  inp.dash = false;

  if (inp.attack && p.attackCd <= 0 && !UI.buildType) swing();

  // Froid et huile de la lanterne
  const lit = lightAt(p.x, p.y);
  if (lit) {
    p.oil = Math.min(p.maxOil, p.oil + 18 * dt);
    if (G.phase !== 'night') p.hp = Math.min(p.maxHp, p.hp + 2 * dt);
    else p.hp = Math.min(p.maxHp, p.hp + 0.6 * dt);
  } else if (G.phase === 'night' || G.phase === 'dusk') {
    p.oil = Math.max(0, p.oil - PLAYER_DEF.oilDrain * dt);
    if (p.oil <= 0) hurtPlayer(PLAYER_DEF.coldDamage * dt, true);
  } else {
    p.hp = Math.min(p.maxHp, p.hp + 1 * dt);
  }
}

function swing() {
  const p = G.player;
  p.attackCd = PLAYER_DEF.cooldown;
  p.swingT = 0.2;
  const range = PLAYER_DEF.range;
  const dmg = PLAYER_DEF.dmg * (1 + 0.25 * G.upgrades.blade);
  const inArc = (x, y, r) => {
    const d = Math.hypot(x - p.x, y - p.y);
    if (d > range + r) return false;
    let da = Math.atan2(y - p.y, x - p.x) - p.facing;
    while (da > Math.PI) da -= Math.PI * 2;
    while (da < -Math.PI) da += Math.PI * 2;
    return Math.abs(da) <= PLAYER_DEF.arc / 2 || d < r + p.radius;
  };
  let hitEnemy = false;
  for (const e of G.enemies) {
    if (e.dead || !inArc(e.x, e.y, e.radius)) continue;
    const lit = lightAt(e.x, e.y);
    damageEnemy(e, dmg * (lit ? 1.5 : 1));
    const a = Math.atan2(e.y - p.y, e.x - p.x);
    const kb = e.def.boss ? 4 : e.type === 'brute' ? 10 : 26;
    moveCircle(e, Math.cos(a) * kb, Math.sin(a) * kb);
    hitEnemy = true;
  }
  if (hitEnemy) return;
  // Récolte : l'objet le plus proche dans l'arc
  let best = null, bestD = Infinity;
  for (const n of G.nodes) {
    if (n.dead || !inArc(n.x, n.y, n.radius)) continue;
    const d = Math.hypot(n.x - p.x, n.y - p.y);
    if (d < bestD) { bestD = d; best = n; }
  }
  if (best) harvest(best);
}

function harvest(n) {
  n.shake = 0.2;
  n.amount--;
  const res = n.def.res;
  const gain = res === 'ember' ? 1 : 1;
  G.res[res] += gain;
  if (res === 'ember') G.stats.embers += gain;
  const names = { wood: 'bois', stone: 'pierre', ember: 'braise' };
  floater(n.x, n.y - 20, `+${gain} ${names[res]}`, res === 'ember' ? '#fb923c' : res === 'wood' ? '#d6b77a' : '#d4d4d8');
  burst(n.x, n.y, res === 'wood' ? '#65a30d' : res === 'ember' ? '#fb923c' : '#a8a29e', 6, 90);
  if (n.amount <= 0) {
    n.dead = true;
    removeEntityFromGrid(n);
    G.depleted.push({ type: n.type, tx: n.tx, ty: n.ty });
    G.flowDirty = true;
  }
}

function hurtPlayer(dmg, cold) {
  const p = G.player;
  if (p.downT > 0) return;
  if (!cold) {
    if (p.invuln > 0) return;
    p.invuln = 0.35;
    p.hitFlash = 0.2;
    cam.shake = 7;
  }
  p.hp -= dmg;
  if (p.hp <= 0) {
    p.hp = 0;
    p.downT = 8;
    burst(p.x, p.y, '#fde68a', 25, 160);
    const cost = Math.min(G.hearth.fuel - 1, 20);
    G.hearth.fuel -= Math.max(0, cost);
    message(cold ? 'Le froid des ténèbres vous a terrassé… La flamme puise dans ses forces pour vous ranimer.'
      : 'Vous êtes tombé… La flamme puise dans ses forces pour vous ranimer.');
  }
}

// Foyer --------------------------------------------------------------------------

function updateHearth(dt) {
  const h = G.hearth;
  h.hitFlash = Math.max(0, h.hitFlash - dt);
  const eco = 1 - 0.08 * G.upgrades.hearth;
  const burn = (G.phase === 'night' ? HEARTH.burnNight : HEARTH.burnDay) * eco;
  h.fuel = Math.max(0, h.fuel - burn * dt);
  if (Math.random() < dt * 14) {
    G.particles.push({ x: h.x + (Math.random() - 0.5) * 30, y: h.y - 10, vx: (Math.random() - 0.5) * 20, vy: -40 - Math.random() * 60, t: 0, life: 1 + Math.random(), color: Math.random() < 0.5 ? '#fb923c' : '#fde047', size: 1.5 + Math.random() * 2 });
  }
  if (G.phase !== 'night') h.hp = Math.min(h.maxHp, h.hp + 3 * dt);
}

// Ombres -------------------------------------------------------------------------

function spawnEnemies(dt) {
  if (G.phase !== 'night') return;
  if (G.bossPending && G.phaseT > 8) {
    const pos = spawnPoint();
    if (pos && addEnemy('devourer', pos.x, pos.y)) G.bossPending = false;
  }
  if (G.spawnLeft <= 0) return;
  G.spawnTimer -= dt;
  if (G.spawnTimer > 0) return;
  const spread = nightLength() * 0.7;
  G.spawnTimer = spread / (4 + G.night * 3) * (0.6 + Math.random() * 0.8);
  // Les ombres arrivent parfois en meute
  const pack = Math.min(G.spawnLeft, 1 + Math.floor(Math.random() * Math.min(4, 1 + G.night / 2)));
  const pos = spawnPoint();
  if (!pos) return;
  for (let i = 0; i < pack; i++) {
    const r = Math.random();
    let type = 'shade';
    if (G.night >= 2 && r < 0.25) type = 'stalker';
    if (G.night >= 3 && r > 0.8) type = 'spitter';
    if (G.night >= 4 && r > 0.93) type = 'brute';
    addEnemy(type, pos.x + (Math.random() - 0.5) * 40, pos.y + (Math.random() - 0.5) * 40);
    G.spawnLeft--;
  }
}

function spawnPoint() {
  const R = hearthRadius();
  for (let tries = 0; tries < 60; tries++) {
    const a = Math.random() * Math.PI * 2;
    const d = R + 480 + Math.random() * 300;
    const x = HEARTH_X + Math.cos(a) * d, y = HEARTH_Y + Math.sin(a) * d;
    const tx = tileOf(x), ty = tileOf(y);
    if (!inMap(tx, ty) || tileSolid(tx, ty) || G.flow[idx(tx, ty)] === Infinity) continue;
    if (Math.hypot(x - G.player.x, y - G.player.y) < 260) continue;
    if (lightAt(x, y)) continue;
    return { x, y };
  }
  return null;
}

function addEnemy(type, x, y) {
  const def = ENEMY_TYPES[type];
  const scale = 1 + (G.night - 1) * 0.1;
  const hp = Math.round(def.hp * scale);
  const e = {
    kind: 'enemy', type, def, x, y, radius: def.radius, hp, maxHp: hp,
    cd: Math.random(), hitFlash: 0, fade: 0, wob: Math.random() * 10, spikeCd: 0, target: null,
    colR: Math.min(def.radius, 14), stuck: 0,
  };
  if (circleHitsSolid(x, y, e.colR)) return null;
  G.enemies.push(e);
  return e;
}

function damageEnemy(e, dmg) {
  if (e.dead) return;
  e.hp -= dmg;
  e.hitFlash = 0.12;
  floater(e.x, e.y - e.radius - 6, Math.round(dmg).toString(), '#fecaca');
  burst(e.x, e.y, '#4c1d95', 5, 80, 0.4);
  if (e.hp <= 0) {
    e.dead = true;
    G.stats.kills++;
    burst(e.x, e.y, e.def.eye, e.def.boss ? 60 : 16, e.def.boss ? 260 : 130, 0.9);
    for (let i = 0; i < e.def.embers; i++) {
      const a = Math.random() * Math.PI * 2, s = 60 + Math.random() * 90;
      G.pickups.push({ x: e.x, y: e.y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, t: 0 });
    }
    if (e.def.boss) message('Le Dévoreur est vaincu ! Ses braises illuminent la nuit.');
  }
}

function updateEnemy(e, dt) {
  e.cd = Math.max(0, e.cd - dt);
  e.spikeCd = Math.max(0, e.spikeCd - dt);
  e.hitFlash = Math.max(0, e.hitFlash - dt);
  e.fade = Math.min(1, e.fade + dt * 1.5);
  e.wob += dt;
  const p = G.player;
  const lit = lightAt(e.x, e.y);
  const speed = e.def.speed * (lit ? 0.62 : 1);
  const pd = Math.hypot(p.x - e.x, p.y - e.y);
  const playerUp = p.downT <= 0;

  // Cracheur : tire à distance
  if (e.def.ranged) {
    let tgt = null;
    if (playerUp && pd < e.def.ranged) tgt = p;
    else {
      const hd = Math.hypot(G.hearth.x - e.x, G.hearth.y - e.y);
      if (hd < e.def.ranged) tgt = G.hearth;
    }
    if (tgt) {
      if (e.cd <= 0) {
        e.cd = e.def.cooldown;
        const a = Math.atan2(tgt.y - e.y, tgt.x - e.x);
        G.projectiles.push({ from: 'enemy', x: e.x, y: e.y, vx: Math.cos(a) * 240, vy: Math.sin(a) * 240, dmg: e.def.dmg, life: 1.6, r: 6, color: e.def.eye });
      }
      return;
    }
  }

  // Chasse le héros s'il est proche (ou toujours pour les rôdeurs)
  const aggro = e.def.huntsPlayer ? 900 : e.def.boss ? 160 : 230;
  if (playerUp && pd < aggro && (pd < 70 || lineClear(e.x, e.y, p.x, p.y))) {
    if (pd < e.radius + p.radius + 4) {
      if (e.cd <= 0) { e.cd = e.def.cooldown; hurtPlayer(e.def.dmg * (lit ? 0.7 : 1)); }
      return;
    }
    const a = Math.atan2(p.y - e.y, p.x - e.x);
    const bx = e.x, by = e.y;
    moveCircle(e, Math.cos(a) * speed * dt, Math.sin(a) * speed * dt);
    // Bloqué par une construction : l'attaquer
    if (Math.hypot(e.x - bx, e.y - by) < speed * dt * 0.3) { attackBlocking(e, a); unstickEnemy(e, dt, speed); }
    return;
  }

  // Suivre le champ de déplacement vers le foyer
  const tx = tileOf(e.x), ty = tileOf(e.y);
  const h = G.hearth;
  if (Math.hypot(h.x - e.x, h.y - e.y) < TILE + e.radius + 6) {
    if (e.cd <= 0) { e.cd = e.def.cooldown; hitStructure(h, e.def.dmg * (e.def.siege || 1) * (lit ? 0.7 : 1)); }
    return;
  }
  const next = G.flow[idx(tx, ty)] === Infinity ? null : nextFlowTile(tx, ty);
  let gx, gy;
  if (next) { gx = next.x * TILE + TILE / 2; gy = next.y * TILE + TILE / 2; }
  else { gx = h.x; gy = h.y; }
  const nb = next ? G.ents.get(G.grid[idx(next.x, next.y)]) : null;
  if (nb && nb.kind === 'building' && nb.solid) {
    if (Math.hypot(nb.x - e.x, nb.y - e.y) < TILE / 2 + e.radius + 8) {
      if (e.cd <= 0) { e.cd = e.def.cooldown; hitStructure(nb, e.def.dmg * (e.def.siege || 1) * (lit ? 0.7 : 1)); }
      return;
    }
  }
  const a = Math.atan2(gy - e.y, gx - e.x);
  const bx = e.x, by = e.y;
  moveCircle(e, Math.cos(a) * speed * dt, Math.sin(a) * speed * dt);
  if (Math.hypot(e.x - bx, e.y - by) < speed * dt * 0.3) {
    attackBlocking(e, a);
    unstickEnemy(e, dt, speed);
  } else e.stuck = 0;
}

// Coincée contre un coin : se recentrer sur sa case, puis tenter un pas de côté
function unstickEnemy(e, dt, speed) {
  e.stuck += dt;
  const cx = tileOf(e.x) * TILE + TILE / 2, cy = tileOf(e.y) * TILE + TILE / 2;
  const a = Math.atan2(cy - e.y, cx - e.x);
  moveCircle(e, Math.cos(a) * speed * dt, Math.sin(a) * speed * dt);
  if (e.stuck > 1.2) {
    const r = Math.random() * Math.PI * 2;
    moveCircle(e, Math.cos(r) * 10, Math.sin(r) * 10);
    e.stuck = 0.6;
  }
}

// Attaque la construction qui bloque le passage dans la direction donnée
function attackBlocking(e, a) {
  const tx = tileOf(e.x + Math.cos(a) * (e.radius + 12)), ty = tileOf(e.y + Math.sin(a) * (e.radius + 12));
  if (!inMap(tx, ty)) return;
  const b = G.ents.get(G.grid[idx(tx, ty)]);
  if (b && (b.kind === 'building' || b.kind === 'hearth') && e.cd <= 0) {
    e.cd = e.def.cooldown;
    hitStructure(b, e.def.dmg * (e.def.siege || 1));
  } else if (!b) {
    // Coincé contre un autre obstacle : petit pas de côté
    moveCircle(e, Math.cos(a + Math.PI / 2) * 6, Math.sin(a + Math.PI / 2) * 6);
  }
}

function hitStructure(b, dmg) {
  b.hp -= dmg;
  b.hitFlash = 0.15;
  burst(b.x, b.y, b.kind === 'hearth' ? '#fb923c' : '#a16207', 4, 70, 0.4);
  if (b.kind === 'building' && b.hp <= 0) destroyBuilding(b);
  if (b.kind === 'hearth' && G.time - (G.hearthWarnAt || -99) > 8) {
    G.hearthWarnAt = G.time;
    message('Le foyer est attaqué !');
  }
}

function separateEnemies() {
  const list = G.enemies;
  for (let i = 0; i < list.length; i++) {
    const a = list[i];
    for (let j = i + 1; j < list.length; j++) {
      const b = list[j];
      const dx = b.x - a.x, dy = b.y - a.y;
      const min = a.radius + b.radius;
      const d2 = dx * dx + dy * dy;
      if (d2 >= min * min || d2 === 0) continue;
      const d = Math.sqrt(d2), push = (min - d) / 2;
      const wa = a.def.boss ? 0.1 : 1, wb = b.def.boss ? 0.1 : 1;
      moveCircle(a, -dx / d * push * wa, -dy / d * push * wa);
      moveCircle(b, dx / d * push * wb, dy / d * push * wb);
    }
  }
}

// Constructions ------------------------------------------------------------------

function updateBuilding(b, dt) {
  b.hitFlash = Math.max(0, b.hitFlash - dt);
  b.built = Math.min(1, b.built + dt * 3);
  if (b.type === 'ballista') {
    b.cd = Math.max(0, b.cd - dt);
    let best = null, bestD = b.def.range;
    for (const e of G.enemies) {
      if (e.dead) continue;
      const d = Math.hypot(e.x - b.x, e.y - b.y) - e.radius;
      if (d < bestD) { bestD = d; best = e; }
    }
    if (best) {
      b.aim = Math.atan2(best.y - b.y, best.x - b.x);
      if (b.cd <= 0) {
        b.cd = b.def.cooldown;
        G.projectiles.push({ from: 'tower', x: b.x, y: b.y, vx: Math.cos(b.aim) * 620, vy: Math.sin(b.aim) * 620, dmg: b.def.dmg, life: 0.6, r: 4, color: '#e7e5e4', target: best });
      }
    }
  } else if (b.type === 'spikes') {
    for (const e of G.enemies) {
      if (e.dead) continue;
      if (tileOf(e.x) === b.tx && tileOf(e.y) === b.ty && e.spikeCd <= 0) {
        e.spikeCd = 0.5;
        damageEnemy(e, b.def.dmg);
        b.hp -= 1;
        if (b.hp <= 0) { destroyBuilding(b); break; }
      }
    }
  }
}

function updateProjectiles(dt) {
  const p = G.player;
  for (const pr of G.projectiles) {
    pr.life -= dt;
    pr.x += pr.vx * dt; pr.y += pr.vy * dt;
    if (pr.life <= 0) { pr.done = true; continue; }
    if (pr.from === 'enemy') {
      if (p.downT <= 0 && Math.hypot(p.x - pr.x, p.y - pr.y) < p.radius + pr.r) { hurtPlayer(pr.dmg); pr.done = true; continue; }
      const tx = tileOf(pr.x), ty = tileOf(pr.y);
      if (inMap(tx, ty)) {
        const b = G.ents.get(G.grid[idx(tx, ty)]);
        if (b && (b.kind === 'building' && b.solid || b.kind === 'hearth')) { hitStructure(b, pr.dmg); pr.done = true; continue; }
      }
    } else {
      for (const e of G.enemies) {
        if (e.dead) continue;
        if (Math.hypot(e.x - pr.x, e.y - pr.y) < e.radius + pr.r) {
          damageEnemy(e, pr.dmg * (lightAt(e.x, e.y) ? 1.5 : 1));
          pr.done = true;
          break;
        }
      }
    }
  }
  G.projectiles = G.projectiles.filter(pr => !pr.done);
}

function updatePickups(dt) {
  const p = G.player;
  for (const k of G.pickups) {
    k.t += dt;
    const d = Math.hypot(p.x - k.x, p.y - k.y);
    if (p.downT <= 0 && d < 130 && k.t > 0.3) {
      const a = Math.atan2(p.y - k.y, p.x - k.x);
      const s = 380 * (1 - d / 160);
      k.vx = Math.cos(a) * s; k.vy = Math.sin(a) * s;
    } else { k.vx *= 0.9; k.vy *= 0.9; }
    k.x += k.vx * dt; k.y += k.vy * dt;
    if (d < p.radius + 6 && k.t > 0.3) {
      k.done = true;
      G.res.ember++;
      G.stats.embers++;
    }
    if (k.t > 40) k.done = true;
  }
  G.pickups = G.pickups.filter(k => !k.done);
}
