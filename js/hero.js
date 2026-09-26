'use strict';

// ---------------------------------------------------------------------------
// Avatars : le seigneur de chaque camp (niveau, aura, cri de guerre, retour)
// ---------------------------------------------------------------------------

function newHeroState(info) {
  return { info, unit: null, level: 1, xp: 0, respawnAt: 0, cryReadyAt: 0, kills: 0 };
}

function heroXpNeeded(level) { return 120 + (level - 1) * 80; }

function makeHeroDef(h) {
  const i = h.info;
  const k = h.level - 1;
  return Object.assign({}, HERO_BASE, {
    name: i.name, title: i.title, look: i.look, desc: i.desc,
    hp: Math.round(i.hp * (1 + 0.12 * k)),
    dmg: Math.round(i.dmg * (1 + 0.1 * k)),
    armor: i.armor + Math.floor(k / 3),
    speed: i.speed, range: i.range, projectile: i.projectile, aura: i.aura,
  });
}

function spawnHero(team) {
  const h = G.heroes[team];
  const hq = G.buildings.find(b => b.team === team && b.type === 'hq' && b.complete) ||
    G.buildings.find(b => b.team === team && b.complete && b.type !== 'wall');
  if (!hq) return null;
  const dir = team === PLAYER ? 1 : -1;
  const u = addUnit('hero', team, hq.x + dir * 10, hq.y - dir * (hq.radius + 34), makeHeroDef(h));
  u.isHero = true;
  unstick(u);
  h.unit = u;
  h.respawnAt = 0;
  return u;
}

function heroOf(team) {
  const h = G.heroes[team];
  return h && h.unit && !h.unit.dead ? h.unit : null;
}

// Aura du seigneur et cri de guerre
function heroDamageMult(attacker) {
  if (attacker.kind !== 'unit' || !G.heroes) return 1;
  let m = 1;
  if (attacker.buffUntil > G.time) m += WARCRY.dmg;
  if (!attacker.isHero) {
    const hero = heroOf(attacker.team);
    if (hero && Math.hypot(hero.x - attacker.x, hero.y - attacker.y) <= AURA_RADIUS) m += hero.def.aura;
  }
  return m;
}

function warCry(team) {
  const h = G.heroes[team];
  const hero = heroOf(team);
  if (!hero || G.time < h.cryReadyAt) return false;
  h.cryReadyAt = G.time + WARCRY.cooldown;
  let n = 0;
  for (const u of G.units) {
    if (u.team !== team || u.type === 'worker') continue;
    if (Math.hypot(u.x - hero.x, u.y - hero.y) <= WARCRY.radius) { u.buffUntil = G.time + WARCRY.duration; n++; }
  }
  G.effects.push({ type: 'warcry', x: hero.x, y: hero.y, team, t: 0, life: 1.0, follow: hero });
  hero.attackAnim = 0.4;
  if (team === PLAYER) notify(`${h.info.name} pousse un cri de guerre ! (${n} soldats galvanisés)`);
  return true;
}

// Expérience et mort
function onKilled(e, killer) {
  if (e.isHero) {
    const h = G.heroes[e.team];
    h.respawnAt = G.time + HERO_RESPAWN;
    if (e.team === PLAYER) notify(`${h.info.name} est tombé au combat ! Retour au château dans ${HERO_RESPAWN} s`);
    else notify(`${h.info.name}, ${h.info.title}, est tombé ! Ses troupes vacillent.`);
  }
  if (!killer || killer.team < 0 || !G.heroes) return;
  const team = killer.team;
  const hero = heroOf(team);
  if (!hero) return;
  let value = e.isHero ? 200 : e.kind === 'unit' ? Math.max(15, e.def.cost * 0.6) : e.type === 'wall' ? 2 : e.def.cost * 0.3;
  if (killer === hero) G.heroes[team].kills++;
  else if (Math.hypot(hero.x - e.x, hero.y - e.y) > AURA_RADIUS * 1.5) return;
  else value *= 0.5;
  grantXp(team, value);
}

function grantXp(team, amount) {
  const h = G.heroes[team];
  if (h.level >= HERO_MAX_LEVEL) return;
  h.xp += amount;
  while (h.level < HERO_MAX_LEVEL && h.xp >= heroXpNeeded(h.level)) {
    h.xp -= heroXpNeeded(h.level);
    h.level++;
    const u = heroOf(team);
    if (u) {
      const frac = u.hp / u.maxHp;
      u.def = makeHeroDef(h);
      u.maxHp = u.def.hp;
      u.hp = Math.min(u.maxHp, u.maxHp * frac + u.maxHp * 0.25);
      G.effects.push({ type: 'levelup', x: u.x, y: u.y, t: 0, life: 1.5, follow: u });
    }
    if (team === PLAYER) notify(`${h.info.name} passe au niveau ${h.level} !`);
  }
  if (h.level >= HERO_MAX_LEVEL) h.xp = 0;
}

function updateHeroes(dt) {
  for (let team = 0; team < 2; team++) {
    const h = G.heroes[team];
    if (heroOf(team)) {
      // Régénération lente hors combat
      const u = h.unit;
      if (!u.lastHit || G.time - u.lastHit > 6) u.hp = Math.min(u.maxHp, u.hp + u.maxHp * 0.01 * dt);
      continue;
    }
    if (!h.respawnAt) h.respawnAt = G.time + HERO_RESPAWN;
    if (G.time >= h.respawnAt) {
      const u = spawnHero(team);
      if (u && team === PLAYER) notify(`${h.info.name} est de retour au château !`);
      if (!u) h.respawnAt = G.time + 5;
    }
  }
}
