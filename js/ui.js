'use strict';

// ---------------------------------------------------------------------------
// Interface, contrôles et boucle principale
// ---------------------------------------------------------------------------

const $ = id => document.getElementById(id);
const canvas = $('game');
const ctx = canvas.getContext('2d');
const minimap = $('minimap');
const mctx = minimap.getContext('2d');

const ui = {
  hover: null,
  drag: null,
  pan: null,
  placing: null, placeTx: 0, placeTy: 0,
  mode: null,           // 'attack' : attente d'une cible pour l'attaque-mouvement
  buildMenu: false,
  markers: [],
  mouse: { x: 0, y: 0, inside: false },
  keys: {},
  lastClick: { t: 0, id: 0 },
  lastGroup: { key: null, t: 0 },
  cardSig: '',
  selSig: '',
  speed: 1,
  difficulty: 'normal',
  running: false,
  minimapDrag: false,
};

let viewW = 0, viewH = 0;
const TOP_H = 40;

function resize() {
  const dpr = window.devicePixelRatio || 1;
  viewW = window.innerWidth;
  viewH = window.innerHeight;
  canvas.width = Math.floor(viewW * dpr);
  canvas.height = Math.floor(viewH * dpr);
  canvas.style.width = viewW + 'px';
  canvas.style.height = viewH + 'px';
  ctx.dpr = dpr;
}
window.addEventListener('resize', resize);
resize();

function bottomH() { return $('bottombar').offsetHeight; }

// Démarrage -------------------------------------------------------------------

function startGame() {
  newGame(ui.difficulty);
  aiReset();
  minimapTerrain = null;
  buildTerrainCanvas();
  ui.placing = null; ui.mode = null; ui.buildMenu = false; ui.markers = [];
  ui.cardSig = ''; ui.selSig = '';
  const hq = G.buildings.find(b => b.team === PLAYER);
  centerOn(hq.x, hq.y);
  $('menu').classList.add('hidden');
  $('endScreen').classList.add('hidden');
  $('pauseScreen').classList.add('hidden');
  ui.running = true;
  notify('Sire, levez votre armée et abattez le château du Seigneur Rouge !');
}

function centerOn(x, y) {
  cam.x = x - viewW / 2 / cam.zoom;
  cam.y = y - (viewH - bottomH() + TOP_H) / 2 / cam.zoom;
  clampCamera(viewW, viewH);
}

document.querySelectorAll('#difficulty button').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('#difficulty button').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    ui.difficulty = btn.dataset.diff;
  });
});
$('startBtn').addEventListener('click', startGame);
$('againBtn').addEventListener('click', () => {
  $('endScreen').classList.add('hidden');
  $('menu').classList.remove('hidden');
  ui.running = false;
});
$('pauseBtn').addEventListener('click', togglePause);
$('resumeBtn').addEventListener('click', togglePause);
$('quitBtn').addEventListener('click', () => {
  G.over = 'defeat';
  G.paused = false;
  $('pauseScreen').classList.add('hidden');
});
$('speedBtn').addEventListener('click', () => {
  ui.speed = ui.speed === 1 ? 1.5 : ui.speed === 1.5 ? 2 : 1;
  $('speedBtn').textContent = 'Vitesse x' + ui.speed;
});
$('idleBtn').addEventListener('click', selectIdleWorker);

function togglePause() {
  if (!G || G.over) return;
  G.paused = !G.paused;
  $('pauseScreen').classList.toggle('hidden', !G.paused);
}

// Sélection -------------------------------------------------------------------

function setSelection(list) {
  G.selection = list;
  ui.buildMenu = false;
  ui.mode = null;
  ui.placing = null;
}

function pickEntity(wx, wy) {
  let best = null, bestD = Infinity;
  for (const u of G.units) {
    if (!isVisibleToPlayer(u)) continue;
    const d = Math.hypot(u.x - wx, u.y - wy);
    if (d <= u.radius + 5 && d < bestD) { bestD = d; best = u; }
  }
  if (best) return best;
  const inRect = e => wx >= e.tx * TILE && wx < (e.tx + e.tw) * TILE && wy >= e.ty * TILE && wy < (e.ty + e.th) * TILE;
  for (const b of G.buildings) {
    if (b.team !== PLAYER && !b.seen) continue;
    if (inRect(b)) return b;
  }
  for (const m of G.mines) {
    if (G.explored[tileIdx(m.tx, m.ty)] && inRect(m)) return m;
  }
  return null;
}

function boxSelect(x0, y0, x1, y1, add) {
  const a = screenToWorld(Math.min(x0, x1), Math.min(y0, y1));
  const b = screenToWorld(Math.max(x0, x1), Math.max(y0, y1));
  let list = G.units.filter(u => u.team === PLAYER && u.x + u.radius >= a.x && u.x - u.radius <= b.x && u.y + u.radius >= a.y && u.y - u.radius <= b.y);
  // Préférer les unités militaires si la sélection est mixte
  const military = list.filter(u => u.type !== 'worker');
  if (military.length && military.length < list.length && !add) list = military;
  if (!list.length) {
    list = G.buildings.filter(bd => bd.team === PLAYER && bd.x >= a.x && bd.x <= b.x && bd.y >= a.y && bd.y <= b.y);
    if (list.length) list = [list[0]];
  }
  if (add) {
    const set = new Set(G.selection.filter(e => e.team === PLAYER && e.kind === 'unit'));
    for (const u of list) if (u.kind === 'unit') set.add(u);
    setSelection([...set]);
  } else {
    setSelection(list);
  }
}

function clickSelect(wx, wy, add, dbl) {
  const e = pickEntity(wx, wy);
  if (!e) { if (!add) setSelection([]); return; }
  if (dbl && e.team === PLAYER) {
    // Tous les éléments du même type visibles à l'écran
    const a = screenToWorld(0, TOP_H), b = screenToWorld(viewW, viewH - bottomH());
    const list = (e.kind === 'unit' ? G.units : G.buildings).filter(o => o.team === PLAYER && o.type === e.type &&
      o.x >= a.x && o.x <= b.x && o.y >= a.y && o.y <= b.y);
    setSelection(list);
    return;
  }
  if (add && e.team === PLAYER && e.kind === 'unit' && G.selection.every(s => s.kind === 'unit' && s.team === PLAYER)) {
    const i = G.selection.indexOf(e);
    const next = G.selection.slice();
    if (i >= 0) next.splice(i, 1); else next.push(e);
    setSelection(next);
    return;
  }
  setSelection([e]);
}

function ownSelectedUnits() { return G.selection.filter(e => e.kind === 'unit' && e.team === PLAYER); }
function ownSelectedBuildings() { return G.selection.filter(e => e.kind === 'building' && e.team === PLAYER); }

function selectIdleWorker() {
  if (!G) return;
  const idle = G.units.filter(u => u.team === PLAYER && u.type === 'worker' && !u.order);
  if (!idle.length) return;
  ui.idleIndex = ((ui.idleIndex || 0) + 1) % idle.length;
  const w = idle[ui.idleIndex];
  setSelection([w]);
  centerOn(w.x, w.y);
}

// Ordres ------------------------------------------------------------------------

function addMarker(x, y, color) { ui.markers.push({ x, y, color, t: 0 }); }

function smartCommand(wx, wy) {
  const units = ownSelectedUnits();
  const target = pickEntity(wx, wy);
  if (units.length) {
    if (target && target.team === ENEMY) {
      commandAttack(units, target);
      addMarker(target.x, target.y, '#f87171');
      return;
    }
    if (target && target.kind === 'mine') {
      commandHarvest(units, target);
      addMarker(target.x, target.y, '#facc15');
      return;
    }
    if (target && target.team === PLAYER && target.kind === 'building') {
      const workers = units.filter(u => u.type === 'worker');
      if (!target.complete && workers.length) {
        commandBuild(workers, target);
        const others = units.filter(u => u.type !== 'worker');
        if (others.length) commandMove(others, wx, wy + target.radius + 30);
        addMarker(target.x, target.y, '#38bdf8');
        return;
      }
      if (target.def.dropoff && workers.some(w => w.carry > 0)) {
        for (const w of workers) if (w.carry > 0) issueOrder(w, { type: 'return', mine: w.lastMine });
        addMarker(target.x, target.y, '#facc15');
        return;
      }
    }
    commandMove(units, wx, wy, false);
    addMarker(wx, wy, '#4ade80');
    return;
  }
  const blds = ownSelectedBuildings().filter(b => b.def.trains);
  if (blds.length) {
    for (const b of blds) b.rally = { x: wx, y: wy, mine: target && target.kind === 'mine' ? target : null };
    addMarker(wx, wy, '#e2e8f0');
  }
}

function startAttackMode() {
  if (!ownSelectedUnits().length) return;
  ui.mode = 'attack';
  ui.placing = null;
}

function startPlacing(type) {
  const def = BUILDING_TYPES[type];
  if (def.requires && !hasBuilding(PLAYER, def.requires, true)) {
    notify(`Nécessite : ${BUILDING_TYPES[def.requires].name}`);
    return;
  }
  if (G.teams[PLAYER].gold < def.cost) { notify("Sire, nos coffres sont vides : pas assez d'or"); return; }
  ui.placing = type;
  ui.mode = null;
}

function placeBuilding(shift) {
  const workers = ownSelectedUnits().filter(u => u.type === 'worker');
  if (!workers.length) { ui.placing = null; return; }
  // Un seul ouvrier (le plus proche) construit ; les autres continuent leurs tâches.
  const def = BUILDING_TYPES[ui.placing];
  const cx = (ui.placeTx + def.w / 2) * TILE, cy = (ui.placeTy + def.h / 2) * TILE;
  // En pose multiple (Maj), les paysans déjà sur un chantier y restent et enchaîneront ensuite.
  const pool = shift ? workers.filter(w => !w.order || w.order.type !== 'build') : workers;
  const builders = pool.length <= 3 ? pool : pool.slice().sort((a, b) =>
    Math.hypot(a.x - cx, a.y - cy) - Math.hypot(b.x - cx, b.y - cy)).slice(0, 3);
  const b = tryPlaceBuilding(PLAYER, ui.placing, ui.placeTx, ui.placeTy, builders);
  if (b) {
    addMarker(b.x, b.y, '#38bdf8');
    if (!shift || G.teams[PLAYER].gold < def.cost) { ui.placing = null; ui.buildMenu = false; }
  }
}

// Carte de commandes -----------------------------------------------------------

function commandCard() {
  const btns = [];
  if (!G) return btns;
  if (ui.placing || ui.mode) {
    btns.push({ id: 'cancel', label: 'Annuler', key: 'ESCAPE', keyLabel: 'Échap', desc: "Annuler l'action en cours.", action: cancelAction });
    return btns;
  }
  const units = ownSelectedUnits();
  const blds = ownSelectedBuildings();
  if (units.length) {
    const workers = units.filter(u => u.type === 'worker');
    if (ui.buildMenu && workers.length) {
      for (const [type, key] of BUILD_ORDER_KEYS) {
        const def = BUILDING_TYPES[type];
        const locked = def.requires && !hasBuilding(PLAYER, def.requires, true);
        btns.push({
          id: 'b_' + type, label: def.name, key, cost: def.cost,
          desc: def.desc + (locked ? `<br><i>Nécessite : ${BUILDING_TYPES[def.requires].name}</i>` : ''),
          disabled: locked || G.teams[PLAYER].gold < def.cost,
          action: () => startPlacing(type),
        });
      }
      btns.push({ id: 'back', label: 'Retour', key: 'ESCAPE', keyLabel: 'Échap', desc: 'Revenir aux ordres.', action: () => { ui.buildMenu = false; } });
      return btns;
    }
    btns.push({ id: 'atk', label: 'Attaquer', key: 'A', desc: "Attaque-mouvement : se déplacer en attaquant tout ennemi rencontré. Cliquez sur une cible ou un point.", action: startAttackMode });
    btns.push({ id: 'stop', label: 'Stop', key: 'S', desc: 'Arrêter toute action.', action: () => commandStop(units) });
    btns.push({ id: 'hold', label: 'Tenir position', key: 'H', desc: "Rester sur place et n'attaquer que les ennemis à portée.", action: () => commandHold(units) });
    if (workers.length) {
      btns.push({ id: 'build', label: 'Construire', key: 'B', desc: 'Ouvrir le menu de construction.', action: () => { ui.buildMenu = true; } });
      btns.push({
        id: 'gather', label: 'Récolter', key: 'G', desc: "Envoyer les paysans sélectionnés à la mine d'or la plus proche.",
        action: () => {
          const m = nearestMine(workers[0].x, workers[0].y);
          if (m) commandHarvest(workers, m);
        },
      });
    }
    return btns;
  }
  if (blds.length) {
    const b = blds[0];
    if (!b.complete) {
      btns.push({
        id: 'cancelb', label: 'Annuler chantier', key: 'X', desc: 'Annuler la construction (75 % du coût remboursé).',
        action: () => {
          G.teams[PLAYER].gold += Math.floor(b.def.cost * 0.75);
          kill(b, null);
          G.teams[PLAYER].stats.buildingsLost--;
        },
      });
      return btns;
    }
    (b.def.trains || []).forEach((type, i) => {
      const def = UNIT_TYPES[type];
      btns.push({
        id: 't_' + type, label: def.name, key: TRAIN_KEYS[i], cost: def.cost,
        desc: `${def.desc}<br>PV ${def.hp} · Dégâts ${def.dmg} · Armure ${def.armor} · Pop ${def.pop} · ${def.time}s`,
        disabled: G.teams[PLAYER].gold < def.cost,
        action: () => {
          // Répartir entre les bâtiments du même type sélectionnés
          const same = blds.filter(o => o.type === b.type && o.complete).sort((x, y) => x.queue.length - y.queue.length);
          queueTraining(same[0], type);
        },
      });
    });
  }
  return btns;
}

function cancelAction() {
  if (ui.placing) { ui.placing = null; return; }
  if (ui.mode) { ui.mode = null; return; }
  if (ui.buildMenu) { ui.buildMenu = false; return; }
  setSelection([]);
}

function refreshCommandCard() {
  const btns = commandCard();
  const sig = btns.map(b => b.id + (b.disabled ? 0 : 1)).join('|') + (ui.mode || '') + (ui.placing || '');
  ui.currentButtons = btns;
  if (sig === ui.cardSig) return;
  ui.cardSig = sig;
  const el = $('commands');
  el.innerHTML = '';
  btns.forEach((b, i) => {
    const d = document.createElement('button');
    d.className = 'cmd' + (b.disabled ? ' disabled' : '') + ((ui.mode === 'attack' && b.id === 'cancel') ? ' active' : '');
    d.innerHTML = `<span class="key">${b.keyLabel || b.key}</span><span>${b.label}</span>` + (b.cost ? `<span class="cost">${b.cost} or</span>` : '');
    d.dataset.index = i;
    el.appendChild(d);
  });
}

$('commands').addEventListener('pointerdown', e => {
  const btn = e.target.closest('.cmd');
  if (!btn || e.button !== 0) return;
  e.preventDefault();
  const b = ui.currentButtons[+btn.dataset.index];
  if (b) b.action();
  ui.cardSig = '';
});
$('commands').addEventListener('mouseover', e => {
  const btn = e.target.closest('.cmd');
  if (!btn) return hideTooltip();
  const b = ui.currentButtons[+btn.dataset.index];
  if (!b) return;
  showTooltip(`<b>${b.label}</b> <span style="color:#a8a29e">[${b.keyLabel || b.key}]</span>` +
    (b.cost ? ` — <span style="color:#facc15">${b.cost} or</span>` : '') + `<br>${b.desc || ''}`, btn);
});
$('commands').addEventListener('mouseleave', hideTooltip);

function showTooltip(html, anchor) {
  const t = $('tooltip');
  t.innerHTML = html;
  t.classList.remove('hidden');
  const r = anchor.getBoundingClientRect();
  t.style.left = Math.max(8, Math.min(window.innerWidth - 270, r.left - 40)) + 'px';
  t.style.top = (r.top - t.offsetHeight - 8) + 'px';
}
function hideTooltip() { $('tooltip').classList.add('hidden'); }

// Panneau de sélection -----------------------------------------------------------

function badgeStyle(e) {
  const c = e.team >= 0 ? TEAM_COLORS[e.team] : '#a16207';
  return `background:${c};`;
}

function hpColor(f) { return f > 0.6 ? '#4ade80' : f > 0.3 ? '#facc15' : '#ef4444'; }

function refreshSelectionPanel() {
  const el = $('selection');
  const sel = G.selection;
  if (!sel.length) {
    if (ui.selSig !== 'none') {
      ui.selSig = 'none';
      el.innerHTML = '<div style="color:#78716c;padding-top:8px">Aucune sélection.<br><br>Astuce : clic gauche pour sélectionner, clic droit pour donner un ordre.</div>';
    }
    return;
  }
  let html;
  if (sel.length === 1) {
    const e = sel[0];
    if (e.kind === 'mine') {
      html = `<div class="sel-single"><div class="portrait" style="background:#a16207">Or</div><div class="sel-info">
        <h3>Mine d'or</h3><div class="desc">Clic droit avec des paysans pour récolter.</div>
        <div>Or restant : <b style="color:#facc15">${Math.floor(e.gold)}</b> / ${e.maxGold}</div></div></div>`;
    } else {
      const def = e.def;
      const f = e.hp / e.maxHp;
      let extra = '';
      if (e.kind === 'unit') {
        const state = unitStateLabel(e);
        extra = `<div class="stats">
          <span>Dégâts</span><b>${def.dmg}${def.splash ? ' (zone)' : ''}</b>
          <span>Armure</span><b>${def.armor}</b>
          <span>Portée</span><b>${def.range > 20 ? def.range : 'mêlée'}</b>
          <span>Vitesse</span><b>${def.speed}</b></div>
          <div style="margin-top:4px;color:#d6d3d1">${state}${e.carry ? ' · transporte ' + e.carry + ' or' : ''}</div>`;
      } else {
        if (!e.complete) {
          extra = `<div>Construction : <b>${Math.floor(e.progress * 100)} %</b></div>`;
        } else {
          const parts = [];
          if (def.dmg) parts.push(`<span>Dégâts</span><b>${def.dmg}</b><span>Portée</span><b>${def.range}</b>`);
          parts.push(`<span>Armure</span><b>${def.armor}</b>`);
          if (def.pop) parts.push(`<span>Population</span><b>+${def.pop}</b>`);
          extra = `<div class="stats">${parts.join('')}</div>`;
          if (e.team === PLAYER && def.trains) {
            extra += '<div class="queue">' + (e.queue.length ? '' : '<span style="color:#78716c">File vide — clic droit sur la carte pour le point de ralliement</span>');
            e.queue.forEach((q, i) => {
              const ud = UNIT_TYPES[q.type];
              extra += `<div class="qitem" data-q="${i}" style="${badgeStyle(e)}" title="Annuler ${ud.name}">${ud.letter}` +
                (i === 0 ? `<div class="prog" style="width:${(q.t / ud.time * 100).toFixed(0)}%"></div>` : '') + '</div>';
            });
            extra += '</div>';
          }
        }
      }
      const letter = e.kind === 'unit' ? def.letter : def.name[0];
      html = `<div class="sel-single"><div class="portrait" style="${badgeStyle(e)}">${letter}</div><div class="sel-info">
        <h3>${def.name}${e.team === ENEMY ? ' <span style="color:#f87171;font-size:12px">(Seigneur Rouge)</span>' : ''}</h3>
        <div class="hpbar"><div style="width:${f * 100}%;background:${hpColor(f)}"></div></div>
        <div style="color:#a8a29e">PV ${Math.ceil(e.hp)} / ${e.maxHp}</div>
        ${extra}</div></div>`;
    }
  } else {
    html = '<div class="sel-multi">' + sel.map((e, i) => {
      const f = e.hp / e.maxHp;
      return `<div class="uicon" data-i="${i}" style="${badgeStyle(e)}" title="${e.def.name}">${e.def.letter || e.def.name[0]}
        <div class="mini"><div style="width:${f * 100}%;background:${hpColor(f)}"></div></div></div>`;
    }).join('') + '</div>';
  }
  if (html !== ui.selSig) {
    ui.selSig = html;
    el.innerHTML = html;
  }
}

function unitStateLabel(u) {
  const o = u.order;
  if (!o) return 'Inactif';
  switch (o.type) {
    case 'move': return 'En déplacement';
    case 'attackMove': return 'Attaque-mouvement';
    case 'attack': return 'Attaque';
    case 'hold': return 'Tient la position';
    case 'harvest': return 'Récolte';
    case 'return': return "Rapporte l'or";
    case 'build': return 'Construit';
  }
  return '';
}

$('selection').addEventListener('pointerdown', e => {
  const q = e.target.closest('.qitem');
  if (q) {
    const b = G.selection[0];
    if (b && b.kind === 'building' && b.team === PLAYER) cancelTraining(b, +q.dataset.q);
    return;
  }
  const u = e.target.closest('.uicon');
  if (u) {
    const ent = G.selection[+u.dataset.i];
    if (!ent) return;
    if (e.shiftKey) setSelection(G.selection.filter(s => s !== ent));
    else if (e.ctrlKey) setSelection(G.selection.filter(s => s.type === ent.type));
    else setSelection([ent]);
  }
});

// Souris sur la carte --------------------------------------------------------------

canvas.addEventListener('contextmenu', e => e.preventDefault());
minimap.addEventListener('contextmenu', e => e.preventDefault());

canvas.addEventListener('mousedown', e => {
  if (!ui.running || !G || G.over) return;
  const w = screenToWorld(e.offsetX, e.offsetY);
  if (e.button === 1) {
    e.preventDefault();
    ui.pan = { x: e.clientX, y: e.clientY, cx: cam.x, cy: cam.y };
    return;
  }
  if (G.paused) return;
  if (e.button === 2) {
    if (ui.placing || ui.mode) { ui.placing = null; ui.mode = null; return; }
    smartCommand(w.x, w.y);
    return;
  }
  if (e.button !== 0) return;
  if (ui.placing) { placeBuilding(e.shiftKey); return; }
  if (ui.mode === 'attack') {
    const units = ownSelectedUnits();
    const t = pickEntity(w.x, w.y);
    if (t && t.team === ENEMY) { commandAttack(units, t); addMarker(t.x, t.y, '#f87171'); }
    else { commandMove(units, w.x, w.y, true); addMarker(w.x, w.y, '#f87171'); }
    if (!e.shiftKey) ui.mode = null;
    return;
  }
  ui.drag = { sx: e.offsetX, sy: e.offsetY, cx: e.offsetX, cy: e.offsetY, active: false, shift: e.shiftKey };
});

window.addEventListener('mousemove', e => {
  const r = canvas.getBoundingClientRect();
  ui.mouse.x = e.clientX - r.left;
  ui.mouse.y = e.clientY - r.top;
  ui.mouse.inWindow = true;
  if (ui.pan) {
    cam.x = ui.pan.cx - (e.clientX - ui.pan.x) / cam.zoom;
    cam.y = ui.pan.cy - (e.clientY - ui.pan.y) / cam.zoom;
    clampCamera(viewW, viewH);
  }
  if (ui.drag) {
    ui.drag.cx = ui.mouse.x; ui.drag.cy = ui.mouse.y;
    if (Math.abs(ui.drag.cx - ui.drag.sx) + Math.abs(ui.drag.cy - ui.drag.sy) > 6) ui.drag.active = true;
  }
});

window.addEventListener('mouseup', e => {
  if (e.button === 1) ui.pan = null;
  if (e.button !== 0) return;
  ui.minimapDrag = false;
  if (!ui.drag || !G) return;
  const d = ui.drag;
  ui.drag = null;
  if (d.active) {
    boxSelect(d.sx, d.sy, d.cx, d.cy, d.shift);
  } else {
    const w = screenToWorld(d.sx, d.sy);
    const now = performance.now();
    const picked = pickEntity(w.x, w.y);
    const dbl = picked && ui.lastClick.id === picked.id && now - ui.lastClick.t < 350;
    ui.lastClick = { t: now, id: picked ? picked.id : 0 };
    clickSelect(w.x, w.y, d.shift, dbl);
  }
});

document.addEventListener('mouseleave', () => { ui.mouse.inWindow = false; });
canvas.addEventListener('mouseenter', () => { ui.mouse.inside = true; });
canvas.addEventListener('mouseleave', () => { ui.mouse.inside = false; });

canvas.addEventListener('wheel', e => {
  if (!ui.running) return;
  e.preventDefault();
  const before = screenToWorld(e.offsetX, e.offsetY);
  cam.zoom = Math.max(0.5, Math.min(1.6, cam.zoom * (e.deltaY < 0 ? 1.1 : 1 / 1.1)));
  cam.x = before.x - e.offsetX / cam.zoom;
  cam.y = before.y - e.offsetY / cam.zoom;
  clampCamera(viewW, viewH);
}, { passive: false });

// Mini-carte
function minimapToWorld(e) {
  const r = minimap.getBoundingClientRect();
  return { x: (e.clientX - r.left) / r.width * WORLD_W, y: (e.clientY - r.top) / r.height * WORLD_H };
}
minimap.addEventListener('mousedown', e => {
  if (!ui.running || !G) return;
  const w = minimapToWorld(e);
  if (e.button === 2) {
    if (!G.paused) smartCommand(w.x, w.y);
    return;
  }
  if (e.button === 0) {
    if (ui.mode === 'attack') {
      commandMove(ownSelectedUnits(), w.x, w.y, true);
      ui.mode = null;
      return;
    }
    ui.minimapDrag = true;
    centerOn(w.x, w.y);
  }
});
minimap.addEventListener('mousemove', e => {
  if (ui.minimapDrag) { const w = minimapToWorld(e); centerOn(w.x, w.y); }
});

// Clavier ----------------------------------------------------------------------------

window.addEventListener('keydown', e => {
  ui.keys[e.key] = true;
  if (!ui.running || !G || G.over) return;
  const key = e.key.toUpperCase();

  if (key === 'P' || (key === 'ESCAPE' && G.paused)) { togglePause(); return; }
  if (G.paused) return;

  // Groupes de contrôle
  if (/^[1-9]$/.test(e.key) || /^Digit[1-9]$/.test(e.code)) {
    const n = e.code.startsWith('Digit') ? e.code.slice(5) : e.key;
    e.preventDefault();
    if (e.ctrlKey || e.metaKey) {
      G.groups[n] = ownSelectedUnits().length ? ownSelectedUnits() : ownSelectedBuildings();
      notify(`Groupe ${n} créé (${G.groups[n].length})`);
    } else if (G.groups[n] && G.groups[n].length) {
      const now = performance.now();
      setSelection(G.groups[n].slice());
      if (ui.lastGroup.key === n && now - ui.lastGroup.t < 400) centerSelection();
      ui.lastGroup = { key: n, t: now };
    }
    return;
  }
  if (key === ' ') { e.preventDefault(); centerSelection(); return; }
  if (key === '.' || key === ';') { selectIdleWorker(); return; }
  if (key.startsWith('ARROW')) { e.preventDefault(); return; }

  // Raccourcis de la carte de commandes
  const btns = commandCard();
  ui.currentButtons = btns;
  const btn = btns.find(b => b.key === key);
  if (btn) {
    e.preventDefault();
    if (!btn.disabled || btn.id.startsWith('b_') || btn.id.startsWith('t_')) btn.action();
    ui.cardSig = '';
    refreshCommandCard();
    return;
  }
  if (key === 'ESCAPE') cancelAction();
});
window.addEventListener('keyup', e => { ui.keys[e.key] = false; });
window.addEventListener('blur', () => { ui.keys = {}; ui.pan = null; ui.drag = null; });

function centerSelection() {
  const s = G.selection.length ? G.selection : G.buildings.filter(b => b.team === PLAYER && b.type === 'hq');
  if (!s.length) return;
  let x = 0, y = 0;
  for (const e of s) { x += e.x; y += e.y; }
  centerOn(x / s.length, y / s.length);
}

// Boucle principale ---------------------------------------------------------------

let last = performance.now();
let uiTimer = 0;

function frame(now) {
  const rawDt = Math.min(0.05, (now - last) / 1000);
  last = now;

  if (ui.running && G) {
    // Caméra
    const speed = 700 / cam.zoom * rawDt;
    if (ui.keys.ArrowLeft) cam.x -= speed;
    if (ui.keys.ArrowRight) cam.x += speed;
    if (ui.keys.ArrowUp) cam.y -= speed;
    if (ui.keys.ArrowDown) cam.y += speed;
    if (ui.mouse.inWindow && !ui.drag && !ui.pan && !ui.minimapDrag && document.hasFocus()) {
      const m = 10;
      if (ui.mouse.x < m) cam.x -= speed;
      if (ui.mouse.x > viewW - m) cam.x += speed;
      if (ui.mouse.y < m) cam.y -= speed;
      if (ui.mouse.y > viewH - m) cam.y += speed;
    }
    clampCamera(viewW, viewH);

    // Simulation (sous-pas pour la stabilité en vitesse accélérée)
    const steps = Math.ceil(ui.speed);
    for (let i = 0; i < steps; i++) update(rawDt * ui.speed / steps);

    for (const m of ui.markers) m.t += rawDt;
    ui.markers = ui.markers.filter(m => m.t < 0.6);

    // Survol et placement
    const w = screenToWorld(ui.mouse.x, ui.mouse.y);
    ui.hover = ui.mouse.inside ? pickEntity(w.x, w.y) : null;
    if (ui.placing) {
      const def = BUILDING_TYPES[ui.placing];
      ui.placeTx = Math.round(w.x / TILE - def.w / 2);
      ui.placeTy = Math.round(w.y / TILE - def.h / 2);
    }
    canvas.classList.toggle('targeting', !!ui.mode);
    canvas.style.cursor = ui.mode ? 'crosshair' : (ui.hover && ui.hover.team === ENEMY && ownSelectedUnits().length ? 'crosshair' : '');

    // Rendu
    render(ctx, viewW, viewH, ui, ctx.dpr || 1);
    renderMinimap(mctx, minimap.width, minimap.height, viewW, viewH);

    uiTimer -= rawDt;
    if (uiTimer <= 0) {
      uiTimer = 0.1;
      refreshHud();
    }

    if (G.over) showEnd();
  }
  requestAnimationFrame(frame);
}

function refreshHud() {
  const t = G.teams[PLAYER];
  $('gold').textContent = Math.floor(t.gold);
  const pop = teamPop(PLAYER);
  $('pop').textContent = `${pop.used}/${pop.cap}`;
  $('pop').classList.toggle('full', pop.used >= pop.cap);
  const idle = G.units.filter(u => u.team === PLAYER && u.type === 'worker' && !u.order).length;
  $('idleCount').textContent = idle;
  $('idleBtn').style.opacity = idle ? 1 : 0.5;
  const s = Math.floor(G.time);
  $('clock').textContent = `${String(Math.floor(s / 60)).padStart(2, '0')}:${String(s % 60).padStart(2, '0')}`;
  $('messages').innerHTML = G.messages.map(m => `<div style="opacity:${Math.min(1, m.t)}">${m.text}</div>`).join('');
  refreshCommandCard();
  refreshSelectionPanel();
}

function showEnd() {
  const win = G.over === 'victory';
  $('endTitle').textContent = win ? 'Victoire ! Le royaume est à vous' : 'Défaite… Votre château est tombé';
  $('endTitle').style.color = win ? '#166534' : '#7a1f14';
  const p = G.teams[PLAYER].stats, e = G.teams[ENEMY].stats;
  const s = Math.floor(G.time);
  const rows = [
    ['Durée', `${Math.floor(s / 60)} min ${s % 60} s`, ''],
    ['Or récolté', p.gathered, e.gathered],
    ['Unités formées', p.trained, e.trained],
    ['Unités ennemies tuées', p.killed, e.killed],
    ['Unités perdues', p.lost, e.lost],
    ['Bâtiments détruits', p.buildingsDestroyed, e.buildingsDestroyed],
  ];
  $('endStats').innerHTML = `<tr><th></th><th style="color:${TEAM_COLORS[0]}">Votre royaume</th><th style="color:${TEAM_COLORS[1]}">Seigneur Rouge</th></tr>` +
    rows.map(r => `<tr><th>${r[0]}</th><td>${r[1]}</td><td>${r[2]}</td></tr>`).join('');
  $('endScreen').classList.remove('hidden');
  ui.running = false;
}

requestAnimationFrame(frame);
