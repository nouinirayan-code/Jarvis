'use strict';

// ---------------------------------------------------------------------------
// Entrées, interface et boucle principale
// ---------------------------------------------------------------------------

const $ = id => document.getElementById(id);
const canvas = $('game');
const ctx = canvas.getContext('2d');
const mini = $('minimap');
const mctx = mini.getContext('2d');

const INPUT = {
  up: false, down: false, left: false, right: false,
  attack: false, dash: false,
  screenX: 0, screenY: 0, mouseX: 0, mouseY: 0,
};
const UI = { buildType: null, running: false, hudTimer: 0, buildSig: '' };

let viewW = 0, viewH = 0, dpr = 1;
function resize() {
  dpr = window.devicePixelRatio || 1;
  viewW = window.innerWidth; viewH = window.innerHeight;
  canvas.width = Math.floor(viewW * dpr); canvas.height = Math.floor(viewH * dpr);
  cam.zoom = viewW < 700 ? 0.8 : viewW < 1100 ? 1 : 1.2;
}
window.addEventListener('resize', resize);
resize();

// Meilleur score (conservé dans le navigateur, si disponible)
function loadBest() { try { return JSON.parse(localStorage.getItem('derniere-lueur-best')) || null; } catch (e) { return null; } }
function saveBest(b) { try { localStorage.setItem('derniere-lueur-best', JSON.stringify(b)); } catch (e) { /* stockage indisponible */ } }
function showBest() {
  const b = loadBest();
  $('best').textContent = b ? `Record : ${b.nights} nuit${b.nights > 1 ? 's' : ''} survécue${b.nights > 1 ? 's' : ''} · ${b.kills} ombres vaincues` : '';
}
showBest();

// Partie -------------------------------------------------------------------------

function start() {
  newGame();
  buildGround();
  miniBase = null;
  UI.buildType = null; UI.buildSig = '';
  cam.x = G.player.x - viewW / 2 / cam.zoom; cam.y = G.player.y - viewH / 2 / cam.zoom;
  for (const id of ['menu', 'gameover', 'pause', 'upgrades']) $(id).classList.add('hidden');
  $('hud').classList.remove('hidden');
  UI.running = true;
  buildBuildBar();
}

$('startBtn').addEventListener('click', start);
$('againBtn').addEventListener('click', start);
$('restartBtn').addEventListener('click', start);
$('resumeBtn').addEventListener('click', togglePause);
$('upClose').addEventListener('click', closeUpgrades);

function togglePause() {
  if (!G || G.over) return;
  if (!$('upgrades').classList.contains('hidden')) { closeUpgrades(); return; }
  G.paused = !G.paused;
  $('pause').classList.toggle('hidden', !G.paused);
}

function gameOver() {
  UI.running = false;
  const s = G.stats;
  const best = loadBest();
  const isRecord = !best || s.nightsSurvived > best.nights || (s.nightsSurvived === best.nights && s.kills > best.kills);
  if (isRecord) saveBest({ nights: s.nightsSurvived, kills: s.kills });
  $('goReason').textContent = G.over.reason;
  const m = Math.floor(G.time / 60), sec = Math.floor(G.time % 60);
  $('goStats').innerHTML = `
    <div>Nuits survécues <b>${s.nightsSurvived}</b></div><div>Ombres vaincues <b>${s.kills}</b></div>
    <div>Braises récoltées <b>${s.embers}</b></div><div>Constructions <b>${s.built}</b></div>
    <div>Temps <b>${m} min ${sec} s</b></div><div>Améliorations <b>${Object.values(G.upgrades).reduce((a, b) => a + b, 0)}</b></div>`;
  $('goBest').textContent = isRecord ? '✦ Nouveau record ! ✦' : `Record : ${best.nights} nuits · ${best.kills} ombres`;
  $('gameover').classList.remove('hidden');
  $('hud').classList.add('hidden');
  showBest();
}

// Améliorations -----------------------------------------------------------------

function nearHearth() { return Math.hypot(G.player.x - HEARTH_X, G.player.y - HEARTH_Y) < 140; }

function openUpgrades() {
  if (!nearHearth()) { message('Approchez-vous du foyer pour les améliorations.'); return; }
  G.paused = true;
  renderUpgrades();
  $('upgrades').classList.remove('hidden');
}
function closeUpgrades() {
  $('upgrades').classList.add('hidden');
  if (G) G.paused = false;
}
function renderUpgrades() {
  $('upEmbers').textContent = G.res.ember;
  $('upList').innerHTML = Object.entries(UPGRADES).map(([key, u], i) => {
    const lv = G.upgrades[key];
    const maxed = lv >= u.max;
    const cost = upgradeCost(key);
    return `<div class="up"><div class="info"><div class="name">${i + 1}. ${u.name}</div><div class="desc">${u.desc}</div>
      <div class="pips">${'◆'.repeat(lv)}${'◇'.repeat(u.max - lv)}</div></div>
      <button data-up="${key}" ${maxed || G.res.ember < cost ? 'disabled' : ''}>${maxed ? 'Maximum' : cost + ' braises'}</button></div>`;
  }).join('');
}
$('upList').addEventListener('click', e => {
  const b = e.target.closest('button[data-up]');
  if (!b) return;
  buyUpgrade(b.dataset.up);
  renderUpgrades();
});

// Barre de construction -------------------------------------------------------------

function buildingIcon(type) {
  const c = document.createElement('canvas');
  c.width = c.height = 88;
  const x = c.getContext('2d');
  x.scale(2, 2);
  const def = BUILD_TYPES[type];
  x.translate(22 - TILE / 2, 26 - TILE / 2);
  drawBuilding(x, { type, def, x: TILE / 2, y: TILE / 2, hp: 1, maxHp: 1, built: 1, hitFlash: 0, aim: -0.6, cd: 0 }, 1.3);
  return c;
}

function buildBuildBar() {
  const bar = $('buildBar');
  bar.innerHTML = '';
  BUILD_ORDER.forEach(type => {
    const def = BUILD_TYPES[type];
    const d = document.createElement('div');
    d.className = 'slot';
    d.dataset.type = type;
    d.title = `${def.name} — ${costText(def.cost)}\n${def.desc}`;
    d.appendChild(buildingIcon(type));
    d.insertAdjacentHTML('afterbegin', `<span class="k">${def.key}</span>`);
    d.insertAdjacentHTML('beforeend', `<span class="c">${Object.entries(def.cost).map(([k, v]) => v + ({ wood: '🪵', stone: '🪨', ember: '🔥' }[k])).join(' ')}</span>`);
    d.addEventListener('mousedown', e => { e.stopPropagation(); selectBuild(type); });
    bar.appendChild(d);
  });
}

function selectBuild(type) {
  UI.buildType = UI.buildType === type ? null : type;
  INPUT.attack = false;
}

// Entrées ------------------------------------------------------------------------

const MOVE_KEYS = {
  KeyW: 'up', ArrowUp: 'up', KeyS: 'down', ArrowDown: 'down',
  KeyA: 'left', ArrowLeft: 'left', KeyD: 'right', ArrowRight: 'right',
};

window.addEventListener('keydown', e => {
  if (!UI.running) return;
  if (MOVE_KEYS[e.code]) { INPUT[MOVE_KEYS[e.code]] = true; e.preventDefault(); return; }
  const upOpen = !$('upgrades').classList.contains('hidden');
  if (e.code === 'Escape') {
    if (upOpen) closeUpgrades();
    else if (UI.buildType) UI.buildType = null;
    else togglePause();
    return;
  }
  if (e.code === 'KeyP') { togglePause(); return; }
  if (upOpen) {
    if (e.code === 'KeyU') closeUpgrades();
    const n = e.code.startsWith('Digit') ? +e.code.slice(5) : 0;
    const key = Object.keys(UPGRADES)[n - 1];
    if (key) { buyUpgrade(key); renderUpgrades(); }
    return;
  }
  if (G.paused) return;
  if (e.code === 'Space' || e.code === 'ShiftLeft' || e.code === 'ShiftRight') { INPUT.dash = true; e.preventDefault(); return; }
  if (e.code.startsWith('Digit') || e.code.startsWith('Numpad')) {
    const n = +e.code.replace(/\D/g, '');
    if (n >= 1 && n <= BUILD_ORDER.length) selectBuild(BUILD_ORDER[n - 1]);
    return;
  }
  if (e.code === 'KeyB') { UI.buildType = UI.buildType ? null : (UI.lastBuild || 'wall'); return; }
  if (e.code === 'KeyF') { feedHearth(); return; }
  if (e.code === 'KeyU') { openUpgrades(); return; }
  if (e.code === 'KeyE') { if (!repairAt(INPUT.mouseX, INPUT.mouseY)) message('Visez une construction abîmée pour la réparer.'); return; }
  if (e.code === 'KeyX') { demolishAt(INPUT.mouseX, INPUT.mouseY); return; }
});
window.addEventListener('keyup', e => {
  if (MOVE_KEYS[e.code]) INPUT[MOVE_KEYS[e.code]] = false;
});
window.addEventListener('blur', () => {
  INPUT.up = INPUT.down = INPUT.left = INPUT.right = INPUT.attack = false;
});

canvas.addEventListener('contextmenu', e => e.preventDefault());
canvas.addEventListener('mousemove', e => { INPUT.screenX = e.clientX; INPUT.screenY = e.clientY; });
canvas.addEventListener('mousedown', e => {
  if (!UI.running || G.paused) return;
  INPUT.screenX = e.clientX; INPUT.screenY = e.clientY;
  if (e.button === 2) { UI.buildType = null; return; }
  if (e.button !== 0) return;
  if (UI.buildType) {
    const w = screenToWorld(e.clientX, e.clientY);
    if (tryBuild(UI.buildType, tileOf(w.x), tileOf(w.y))) UI.lastBuild = UI.buildType;
    return;
  }
  INPUT.attack = true;
});
window.addEventListener('mouseup', e => { if (e.button === 0) INPUT.attack = false; });

// HUD -----------------------------------------------------------------------------

function setBar(id, frac) { $(id).style.width = Math.max(0, Math.min(1, frac)) * 100 + '%'; }

function refreshHud() {
  const p = G.player, h = G.hearth;
  setBar('hpBar', p.hp / p.maxHp);
  $('hpTxt').textContent = p.downT > 0 ? `Ranimé dans ${Math.ceil(p.downT)} s` : `${Math.ceil(p.hp)} / ${p.maxHp}`;
  setBar('oilBar', p.oil / p.maxOil);
  $('oilTxt').textContent = p.oil > 0 ? 'Huile de lanterne' : 'Lanterne vide : le froid vous ronge !';
  setBar('dashBar', 1 - p.dashCd / PLAYER_DEF.dashCooldown);

  const night = G.phase === 'night' || G.phase === 'dusk';
  const label = { day: 'Jour', dusk: 'Crépuscule', night: 'Nuit', dawn: 'Aube' }[G.phase];
  const num = G.phase === 'night' ? G.night : G.night + 1;
  $('phaseName').textContent = `${label} ${G.phase === 'dusk' ? '' : num} · ${Math.ceil(phaseRemaining())} s`;
  $('phaseName').classList.toggle('night', night);
  const total = G.phase === 'day' ? DAY_LENGTH + DUSK_LENGTH : G.phase === 'night' ? nightLength() : G.phase === 'dusk' ? DUSK_LENGTH : 4;
  setBar('phaseBar', phaseRemaining() / total);
  $('phaseBar').classList.toggle('night', night);
  setBar('fuelBar', h.fuel / HEARTH.maxFuel);
  $('fuelTxt').textContent = `Flamme ${Math.ceil(h.fuel)} %`;
  setBar('hearthBar', h.hp / h.maxHp);

  const boss = G.enemies.find(e => e.def.boss);
  $('bossBar').classList.toggle('hidden', !boss);
  if (boss) setBar('bossFill', boss.hp / boss.maxHp);

  $('rWood').textContent = G.res.wood;
  $('rStone').textContent = G.res.stone;
  $('rEmber').textContent = G.res.ember;

  for (const s of document.querySelectorAll('.slot')) {
    const type = s.dataset.type;
    s.classList.toggle('active', UI.buildType === type);
    s.classList.toggle('poor', !canAfford(BUILD_TYPES[type].cost));
  }

  let hint = '';
  if (p.downT > 0) hint = 'La flamme vous ranime…';
  else if (UI.buildType) hint = `${BUILD_TYPES[UI.buildType].name} : clic pour bâtir (zone éclairée) · clic droit pour annuler`;
  else if (nearHearth()) hint = `F : nourrir la flamme (${G.res.ember ? '1 braise' : 'bois'}) · U : améliorations`;
  else if (G.phase === 'day' && G.time < 25) hint = 'Frappez les arbres et les rochers pour récolter · 1 à 5 pour construire';
  else if (G.phase === 'dusk') hint = 'La nuit tombe : revenez défendre le foyer !';
  $('hint').textContent = hint;

  $('messages').innerHTML = G.messages.map(m => `<div style="opacity:${Math.min(1, m.t)}">${m.text}</div><br>`).join('');
}

// Boucle --------------------------------------------------------------------------

let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (UI.running && G) {
    const w = screenToWorld(INPUT.screenX, INPUT.screenY);
    INPUT.mouseX = w.x; INPUT.mouseY = w.y;
    update(dt);
    updateCamera(dt, viewW, viewH);
    render(ctx, viewW, viewH, dpr);
    renderMinimap(mctx, mini.width, mini.height);
    UI.hudTimer -= dt;
    if (UI.hudTimer <= 0) { UI.hudTimer = 0.1; refreshHud(); }
    if (G.over) gameOver();
  }
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
