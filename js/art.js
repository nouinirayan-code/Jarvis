'use strict';

// ---------------------------------------------------------------------------
// Illustrations : portraits des seigneurs et icônes de l'interface
// ---------------------------------------------------------------------------

const ICON_CACHE = new Map();

// Portrait en buste dessiné dans un carré de taille S.
function drawPortrait(c, look, team, S) {
  const k = S / 100;
  c.save();
  c.scale(k, k);
  const col = TEAM_COLORS[team], dark = TEAM_DARK[team];

  // Fond
  const bg = c.createRadialGradient(50, 40, 10, 50, 50, 75);
  bg.addColorStop(0, team === PLAYER ? '#4b6fae' : '#a44a3a');
  bg.addColorStop(1, team === PLAYER ? '#101c36' : '#2a0c08');
  c.fillStyle = bg;
  c.fillRect(0, 0, 100, 100);
  // rayons de lumière
  c.globalAlpha = 0.08; c.fillStyle = '#fff';
  for (let i = 0; i < 8; i++) {
    c.beginPath(); c.moveTo(50, 40);
    const a = i / 8 * Math.PI * 2;
    c.lineTo(50 + Math.cos(a) * 90, 40 + Math.sin(a) * 90);
    c.lineTo(50 + Math.cos(a + 0.2) * 90, 40 + Math.sin(a + 0.2) * 90);
    c.fill();
  }
  c.globalAlpha = 1;

  const skin = '#e9b996', skinShade = '#c98f6c';

  // Cape et épaules
  c.fillStyle = look === 'blackknight' ? '#1c1917' : look === 'redlord' ? '#450a0a' : dark;
  c.beginPath(); c.moveTo(4, 100); c.quadraticCurveTo(10, 66, 50, 66); c.quadraticCurveTo(90, 66, 96, 100); c.fill();
  const armor = look === 'blackknight' ? '#3f3f46' : look === 'redlord' ? '#57534e' : '#a1a1aa';
  if (look === 'queen') {
    c.fillStyle = col;
    c.beginPath(); c.moveTo(16, 100); c.quadraticCurveTo(22, 74, 50, 72); c.quadraticCurveTo(78, 74, 84, 100); c.fill();
    c.strokeStyle = '#facc15'; c.lineWidth = 2;
    c.beginPath(); c.moveTo(34, 76); c.quadraticCurveTo(50, 90, 66, 76); c.stroke();
    c.fillStyle = '#facc15'; c.beginPath(); c.arc(50, 86, 3, 0, Math.PI * 2); c.fill();
  } else {
    c.fillStyle = armor;
    c.beginPath(); c.ellipse(27, 80, 17, 11, -0.3, 0, Math.PI * 2); c.fill();
    c.beginPath(); c.ellipse(73, 80, 17, 11, 0.3, 0, Math.PI * 2); c.fill();
    c.fillRect(32, 74, 36, 26);
    c.strokeStyle = 'rgba(0,0,0,0.35)'; c.lineWidth = 1.5;
    c.beginPath(); c.moveTo(50, 76); c.lineTo(50, 100); c.stroke();
    // tabard / blason
    c.fillStyle = look === 'blackknight' ? '#27272a' : col;
    c.beginPath(); c.moveTo(38, 80); c.lineTo(62, 80); c.lineTo(62, 94); c.lineTo(50, 100); c.lineTo(38, 94); c.fill();
    c.fillStyle = look === 'redlord' ? '#fbbf24' : '#f5f5f4';
    c.beginPath(); c.moveTo(50, 83); c.lineTo(55, 89); c.lineTo(50, 95); c.lineTo(45, 89); c.fill();
  }

  // Cou
  c.fillStyle = skinShade; c.fillRect(43, 60, 14, 12);

  if (look === 'blackknight') {
    // Heaume
    const g = c.createLinearGradient(30, 20, 70, 70);
    g.addColorStop(0, '#71717a'); g.addColorStop(1, '#18181b');
    c.fillStyle = g;
    c.beginPath(); c.moveTo(29, 66); c.lineTo(29, 34); c.quadraticCurveTo(29, 16, 50, 15); c.quadraticCurveTo(71, 16, 71, 34); c.lineTo(71, 66); c.closePath(); c.fill();
    c.strokeStyle = '#09090b'; c.lineWidth = 1.5; c.stroke();
    c.fillStyle = '#09090b'; c.fillRect(33, 40, 34, 4);
    c.fillStyle = '#ef4444'; c.globalAlpha = 0.8; c.fillRect(38, 41, 7, 2); c.fillRect(55, 41, 7, 2); c.globalAlpha = 1;
    c.strokeStyle = '#09090b'; c.beginPath(); c.moveTo(50, 44); c.lineTo(50, 64); c.stroke();
    for (let i = 0; i < 4; i++) { c.fillStyle = '#09090b'; c.fillRect(40 + i * 6, 52, 2, 6); }
    // Panache
    c.fillStyle = col;
    c.beginPath(); c.moveTo(50, 16); c.quadraticCurveTo(64, 0, 84, 8); c.quadraticCurveTo(70, 8, 62, 22); c.fill();
  } else if (look === 'redlord') {
    // Visage dur, casque cornu
    c.fillStyle = skin; c.beginPath(); c.ellipse(50, 46, 18, 22, 0, 0, Math.PI * 2); c.fill();
    c.fillStyle = '#1c1917';
    c.beginPath(); c.moveTo(33, 50); c.quadraticCurveTo(36, 72, 50, 72); c.quadraticCurveTo(64, 72, 67, 50); c.quadraticCurveTo(60, 60, 50, 58); c.quadraticCurveTo(40, 60, 33, 50); c.fill();
    c.fillStyle = '#fff'; c.fillRect(40, 42, 7, 3); c.fillRect(53, 42, 7, 3);
    c.fillStyle = '#7f1d1d'; c.fillRect(42, 42, 3, 3); c.fillRect(55, 42, 3, 3);
    c.strokeStyle = '#1c1917'; c.lineWidth = 2.5;
    c.beginPath(); c.moveTo(38, 38); c.lineTo(47, 41); c.moveTo(62, 38); c.lineTo(53, 41); c.stroke();
    c.strokeStyle = '#9f1239'; c.lineWidth = 1.2; c.beginPath(); c.moveTo(58, 46); c.lineTo(63, 55); c.stroke();
    c.fillStyle = '#7f1d1d';
    c.beginPath(); c.moveTo(30, 40); c.quadraticCurveTo(30, 20, 50, 19); c.quadraticCurveTo(70, 20, 70, 40); c.lineTo(66, 36); c.lineTo(34, 36); c.closePath(); c.fill();
    c.fillStyle = '#e7e5e4';
    c.beginPath(); c.moveTo(32, 30); c.quadraticCurveTo(14, 26, 12, 8); c.quadraticCurveTo(22, 20, 34, 24); c.fill();
    c.beginPath(); c.moveTo(68, 30); c.quadraticCurveTo(86, 26, 88, 8); c.quadraticCurveTo(78, 20, 66, 24); c.fill();
  } else {
    const queen = look === 'queen';
    // Cheveux arrière
    c.fillStyle = queen ? '#9a3412' : '#6b4423';
    if (queen) { c.beginPath(); c.moveTo(28, 44); c.quadraticCurveTo(24, 76, 34, 80); c.lineTo(66, 80); c.quadraticCurveTo(76, 76, 72, 44); c.fill(); }
    // Visage
    c.fillStyle = skin; c.beginPath(); c.ellipse(50, 46, queen ? 17 : 18, queen ? 21 : 22, 0, 0, Math.PI * 2); c.fill();
    c.fillStyle = skinShade; c.beginPath(); c.ellipse(50, 52, 3, 5, 0, 0, Math.PI * 2); c.fill();
    // Yeux
    c.fillStyle = '#fff'; c.beginPath(); c.ellipse(43, 44, 3.5, 2.2, 0, 0, Math.PI * 2); c.ellipse(57, 44, 3.5, 2.2, 0, 0, Math.PI * 2); c.fill();
    c.fillStyle = queen ? '#166534' : '#1e3a8a'; c.beginPath(); c.arc(43, 44, 1.6, 0, Math.PI * 2); c.arc(57, 44, 1.6, 0, Math.PI * 2); c.fill();
    c.strokeStyle = queen ? '#7c2d12' : '#4a2f18'; c.lineWidth = 2;
    c.beginPath(); c.moveTo(38, 39); c.quadraticCurveTo(43, 37, 47, 39); c.moveTo(53, 39); c.quadraticCurveTo(57, 37, 62, 39); c.stroke();
    if (queen) {
      c.fillStyle = '#be123c'; c.beginPath(); c.ellipse(50, 59, 4, 1.8, 0, 0, Math.PI * 2); c.fill();
      c.fillStyle = 'rgba(244,114,182,0.3)'; c.beginPath(); c.arc(40, 52, 4, 0, Math.PI * 2); c.arc(60, 52, 4, 0, Math.PI * 2); c.fill();
      // Cheveux avant
      c.fillStyle = '#9a3412';
      c.beginPath(); c.moveTo(32, 46); c.quadraticCurveTo(30, 22, 50, 23); c.quadraticCurveTo(70, 22, 68, 46); c.quadraticCurveTo(64, 32, 50, 30); c.quadraticCurveTo(36, 32, 32, 46); c.fill();
      // Diadème
      c.fillStyle = '#e5e7eb';
      c.beginPath(); c.moveTo(35, 29); c.quadraticCurveTo(50, 22, 65, 29); c.lineTo(62, 24); c.lineTo(56, 22); c.lineTo(50, 14); c.lineTo(44, 22); c.lineTo(38, 24); c.closePath(); c.fill();
      c.fillStyle = col; c.beginPath(); c.arc(50, 22, 2.5, 0, Math.PI * 2); c.fill();
    } else {
      // Barbe et moustache
      c.fillStyle = '#6b4423';
      c.beginPath(); c.moveTo(32, 48); c.quadraticCurveTo(34, 76, 50, 76); c.quadraticCurveTo(66, 76, 68, 48); c.quadraticCurveTo(62, 60, 50, 59); c.quadraticCurveTo(38, 60, 32, 48); c.fill();
      c.beginPath(); c.moveTo(40, 57); c.quadraticCurveTo(50, 51, 60, 57); c.quadraticCurveTo(50, 55, 40, 57); c.fill();
      c.fillStyle = '#6b4423';
      c.beginPath(); c.moveTo(31, 44); c.quadraticCurveTo(29, 24, 50, 24); c.quadraticCurveTo(71, 24, 69, 44); c.quadraticCurveTo(66, 32, 50, 31); c.quadraticCurveTo(34, 32, 31, 44); c.fill();
      // Couronne
      const g = c.createLinearGradient(0, 10, 0, 32);
      g.addColorStop(0, '#fde68a'); g.addColorStop(1, '#b45309');
      c.fillStyle = g;
      c.beginPath(); c.moveTo(32, 32); c.lineTo(32, 14); c.lineTo(39, 22); c.lineTo(44, 10); c.lineTo(50, 20); c.lineTo(56, 10); c.lineTo(61, 22); c.lineTo(68, 14); c.lineTo(68, 32); c.closePath(); c.fill();
      c.strokeStyle = '#78350f'; c.lineWidth = 1; c.stroke();
      c.fillStyle = '#dc2626'; c.beginPath(); c.arc(50, 27, 2.5, 0, Math.PI * 2); c.fill();
      c.fillStyle = col; c.beginPath(); c.arc(39, 28, 2, 0, Math.PI * 2); c.arc(61, 28, 2, 0, Math.PI * 2); c.fill();
    }
  }
  c.restore();
}

function portraitURL(look, team, size) {
  const key = `p:${look}:${team}:${size}`;
  if (ICON_CACHE.has(key)) return ICON_CACHE.get(key);
  const cv = document.createElement('canvas');
  cv.width = cv.height = size;
  drawPortrait(cv.getContext('2d'), look, team, size);
  const url = cv.toDataURL();
  ICON_CACHE.set(key, url);
  return url;
}

// Icône d'une unité ou d'un bâtiment, dessinée avec le même style que sur la carte.
function entityIconURL(kind, type, team, size, look) {
  size = size || 64;
  if (kind === 'unit' && type === 'hero') return portraitURL(look || 'king', team, size);
  const key = `e:${kind}:${type}:${team}:${size}`;
  if (ICON_CACHE.has(key)) return ICON_CACHE.get(key);
  const cv = document.createElement('canvas');
  cv.width = cv.height = size;
  const c = cv.getContext('2d');
  const bg = c.createLinearGradient(0, 0, 0, size);
  bg.addColorStop(0, '#7a9a5a'); bg.addColorStop(1, '#4d6b36');
  c.fillStyle = bg; c.fillRect(0, 0, size, size);
  if (kind === 'unit') {
    const def = UNIT_TYPES[type];
    const k = size / (def.radius * 3.4);
    c.save(); c.scale(k, k);
    drawUnit(c, {
      x: size / 2 / k, y: size / 2 / k + 1, type, team, def, radius: def.radius,
      facing: -0.7, attackAnim: 0, carry: type === 'worker' ? 10 : 0, hp: 1, maxHp: 1,
    }, false, false);
    c.restore();
  } else if (kind === 'building') {
    const def = BUILDING_TYPES[type];
    const w = def.w * TILE, h = def.h * TILE;
    const k = size / (Math.max(w, h) + 10);
    c.save(); c.scale(k, k); c.translate(5 + (Math.max(w, h) - w) / 2, 5 + (Math.max(w, h) - h) / 2);
    drawBuildingBody(c, { type, team, tx: -1000, ty: -1000, tw: def.w, th: def.h, x: w / 2, y: h / 2 },
      0, 0, w, h, TEAM_COLORS[team], TEAM_DARK[team], 1);
    c.restore();
  } else if (kind === 'mine') {
    const k = size / 72;
    c.save(); c.scale(k, k); c.translate(4, 4);
    drawMine(c, { tx: 0, ty: 0, tw: 2, th: 2, x: 32, y: 32, radius: 32, gold: 1, maxGold: 1 });
    c.restore();
  }
  const url = cv.toDataURL();
  ICON_CACHE.set(key, url);
  return url;
}

// Icônes des ordres
function commandIconURL(id, size) {
  size = size || 48;
  const key = `c:${id}:${size}`;
  if (ICON_CACHE.has(key)) return ICON_CACHE.get(key);
  const cv = document.createElement('canvas');
  cv.width = cv.height = size;
  const c = cv.getContext('2d');
  c.scale(size / 48, size / 48);
  c.lineCap = 'round'; c.lineJoin = 'round';
  const steel = '#e5e7eb', wood = '#a16207', gold = '#facc15';
  const sword = (a) => {
    c.save(); c.translate(24, 24); c.rotate(a);
    c.fillStyle = steel; c.beginPath(); c.moveTo(-2, 8); c.lineTo(-2, -16); c.lineTo(0, -20); c.lineTo(2, -16); c.lineTo(2, 8); c.fill();
    c.fillStyle = gold; c.fillRect(-7, 8, 14, 3);
    c.fillStyle = '#78350f'; c.fillRect(-1.5, 11, 3, 7);
    c.fillStyle = gold; c.beginPath(); c.arc(0, 19, 2.2, 0, Math.PI * 2); c.fill();
    c.restore();
  };
  const shield = (fill) => {
    c.fillStyle = fill; c.strokeStyle = gold; c.lineWidth = 2.5;
    c.beginPath(); c.moveTo(10, 9); c.lineTo(38, 9); c.lineTo(38, 24); c.quadraticCurveTo(38, 37, 24, 42); c.quadraticCurveTo(10, 37, 10, 24); c.closePath(); c.fill(); c.stroke();
  };
  switch (id) {
    case 'atk': sword(-0.75); sword(0.75); break;
    case 'stop': shield('#7f1d1d'); c.fillStyle = steel; c.fillRect(17, 18, 14, 14); break;
    case 'hold': shield(TEAM_COLORS[PLAYER]); c.strokeStyle = steel; c.lineWidth = 3; c.beginPath(); c.moveTo(24, 14); c.lineTo(24, 34); c.moveTo(16, 22); c.lineTo(32, 22); c.stroke(); break;
    case 'build':
      c.save(); c.translate(24, 24); c.rotate(-0.6);
      c.fillStyle = wood; c.fillRect(-2, -6, 4, 24);
      c.fillStyle = '#9ca3af'; c.fillRect(-10, -14, 20, 9);
      c.restore(); break;
    case 'gather':
      c.fillStyle = gold; for (const [x, y] of [[14, 36], [24, 38], [34, 35], [19, 30], [29, 30]]) { c.beginPath(); c.arc(x, y, 5, 0, Math.PI * 2); c.fill(); }
      c.strokeStyle = wood; c.lineWidth = 3; c.beginPath(); c.moveTo(12, 8); c.lineTo(34, 28); c.stroke();
      c.strokeStyle = '#9ca3af'; c.lineWidth = 4; c.beginPath(); c.moveTo(8, 16); c.quadraticCurveTo(16, 6, 26, 4); c.stroke(); break;
    case 'warcry':
      c.fillStyle = '#e7d3a7'; c.strokeStyle = '#78350f'; c.lineWidth = 2;
      c.beginPath(); c.moveTo(8, 30); c.quadraticCurveTo(16, 18, 34, 12); c.lineTo(38, 22); c.quadraticCurveTo(22, 26, 12, 36); c.closePath(); c.fill(); c.stroke();
      c.strokeStyle = gold; c.lineWidth = 2;
      for (let i = 0; i < 3; i++) { c.beginPath(); c.arc(38, 17, 5 + i * 4, -0.9, 0.9); c.stroke(); }
      break;
    case 'hero':
      c.fillStyle = gold; c.strokeStyle = '#78350f'; c.lineWidth = 1.5;
      c.beginPath(); c.moveTo(8, 36); c.lineTo(8, 14); c.lineTo(16, 24); c.lineTo(24, 8); c.lineTo(32, 24); c.lineTo(40, 14); c.lineTo(40, 36); c.closePath(); c.fill(); c.stroke();
      c.fillStyle = '#dc2626'; c.beginPath(); c.arc(24, 30, 3, 0, Math.PI * 2); c.fill(); break;
    case 'back':
      c.strokeStyle = steel; c.lineWidth = 4; c.beginPath(); c.moveTo(36, 24); c.lineTo(12, 24); c.moveTo(20, 14); c.lineTo(10, 24); c.lineTo(20, 34); c.stroke(); break;
    default:
      c.strokeStyle = '#f87171'; c.lineWidth = 5; c.beginPath(); c.moveTo(12, 12); c.lineTo(36, 36); c.moveTo(36, 12); c.lineTo(12, 36); c.stroke();
  }
  const url = cv.toDataURL();
  ICON_CACHE.set(key, url);
  return url;
}
