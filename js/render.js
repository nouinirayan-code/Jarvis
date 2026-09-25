'use strict';

// ---------------------------------------------------------------------------
// Rendu : terrain, entités, brouillard, mini-carte
// ---------------------------------------------------------------------------

const cam = { x: 0, y: 0, zoom: 1 };
let terrainCanvas = null;
let fogCanvas = null, fogCtx = null, fogImg = null;

function buildTerrainCanvas() {
  terrainCanvas = document.createElement('canvas');
  terrainCanvas.width = WORLD_W;
  terrainCanvas.height = WORLD_H;
  const c = terrainCanvas.getContext('2d');
  const rng = mulberry32(G.seed ^ 0x5bd1e995);

  for (let ty = 0; ty < MAP_H; ty++) {
    for (let tx = 0; tx < MAP_W; tx++) {
      const x = tx * TILE, y = ty * TILE;
      const n = rng();
      c.fillStyle = `hsl(${95 + n * 12}, ${38 + n * 8}%, ${30 + n * 5}%)`;
      c.fillRect(x, y, TILE, TILE);
      for (let k = 0; k < 4; k++) {
        c.fillStyle = rng() < 0.5 ? 'rgba(255,255,200,0.05)' : 'rgba(0,40,0,0.08)';
        c.fillRect(x + rng() * TILE, y + rng() * TILE, 2 + rng() * 3, 2 + rng() * 3);
      }
    }
  }
  // Eau
  for (let ty = 0; ty < MAP_H; ty++) {
    for (let tx = 0; tx < MAP_W; tx++) {
      if (G.terrain[tileIdx(tx, ty)] !== T_WATER) continue;
      const x = tx * TILE, y = ty * TILE;
      c.fillStyle = '#c2b280';
      c.fillRect(x - 3, y - 3, TILE + 6, TILE + 6);
    }
  }
  for (let ty = 0; ty < MAP_H; ty++) {
    for (let tx = 0; tx < MAP_W; tx++) {
      if (G.terrain[tileIdx(tx, ty)] !== T_WATER) continue;
      const x = tx * TILE, y = ty * TILE;
      c.fillStyle = `hsl(205, 60%, ${34 + rng() * 4}%)`;
      c.fillRect(x, y, TILE, TILE);
      c.strokeStyle = 'rgba(255,255,255,0.15)';
      c.beginPath();
      const wy = y + 8 + rng() * 16, wx = x + rng() * 12;
      c.moveTo(wx, wy); c.quadraticCurveTo(wx + 5, wy - 3, wx + 10, wy);
      c.stroke();
    }
  }
  // Forêts
  for (let ty = 0; ty < MAP_H; ty++) {
    for (let tx = 0; tx < MAP_W; tx++) {
      if (G.terrain[tileIdx(tx, ty)] !== T_FOREST) continue;
      const x = tx * TILE, y = ty * TILE;
      c.fillStyle = 'rgba(20,50,20,0.5)';
      c.fillRect(x, y, TILE, TILE);
      for (let k = 0; k < 3; k++) {
        const px = x + 6 + rng() * 20, py = y + 6 + rng() * 20, r = 7 + rng() * 5;
        c.fillStyle = 'rgba(0,0,0,0.3)';
        c.beginPath(); c.arc(px + 3, py + 4, r, 0, Math.PI * 2); c.fill();
        c.fillStyle = `hsl(${120 + rng() * 25}, 45%, ${18 + rng() * 10}%)`;
        c.beginPath(); c.arc(px, py, r, 0, Math.PI * 2); c.fill();
        c.fillStyle = 'rgba(255,255,255,0.08)';
        c.beginPath(); c.arc(px - r / 3, py - r / 3, r / 2, 0, Math.PI * 2); c.fill();
      }
    }
  }

  fogCanvas = document.createElement('canvas');
  fogCanvas.width = MAP_W;
  fogCanvas.height = MAP_H;
  fogCtx = fogCanvas.getContext('2d');
  fogImg = fogCtx.createImageData(MAP_W, MAP_H);
}

function updateFogCanvas() {
  const d = fogImg.data;
  for (let i = 0; i < MAP_W * MAP_H; i++) {
    const a = G.visible[i] ? 0 : (G.explored[i] ? 130 : 255);
    d[i * 4] = 8; d[i * 4 + 1] = 10; d[i * 4 + 2] = 14; d[i * 4 + 3] = a;
  }
  fogCtx.putImageData(fogImg, 0, 0);
}

function worldToScreen(x, y) { return { x: (x - cam.x) * cam.zoom, y: (y - cam.y) * cam.zoom }; }
function screenToWorld(x, y) { return { x: x / cam.zoom + cam.x, y: y / cam.zoom + cam.y }; }

function clampCamera(viewW, viewH) {
  const vw = viewW / cam.zoom, vh = viewH / cam.zoom;
  cam.x = Math.max(-40, Math.min(WORLD_W - vw + 40, cam.x));
  cam.y = Math.max(-40 - 40 / cam.zoom, Math.min(WORLD_H - vh + 40 + 180 / cam.zoom, cam.y));
}

function render(ctx, W, H, ui, dpr) {
  dpr = dpr || 1;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = '#0b0d12';
  ctx.fillRect(0, 0, W, H);
  const z = cam.zoom * dpr;
  ctx.setTransform(z, 0, 0, z, -cam.x * z, -cam.y * z);

  const vx0 = cam.x - 64, vy0 = cam.y - 64, vx1 = cam.x + W / cam.zoom + 64, vy1 = cam.y + H / cam.zoom + 64;
  const inView = e => e.x > vx0 - e.radius && e.x < vx1 + e.radius && e.y > vy0 - e.radius && e.y < vy1 + e.radius;

  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(terrainCanvas, 0, 0);

  // Décombres et traces
  for (const e of G.effects) {
    if (e.type === 'rubble') {
      ctx.globalAlpha = 0.6 * (1 - e.t / e.life);
      ctx.fillStyle = '#3d3429';
      ctx.fillRect(e.x - e.w / 2 + 4, e.y - e.h / 2 + 4, e.w - 8, e.h - 8);
      ctx.globalAlpha = 1;
    }
  }

  // Mines
  for (const m of G.mines) if (inView(m) && G.explored[tileIdx(m.tx, m.ty)]) drawMine(ctx, m);

  // Bâtiments
  for (const b of G.buildings) {
    if (!inView(b)) continue;
    if (b.team !== PLAYER && !b.seen) continue;
    drawBuilding(ctx, b, ui);
  }

  // Cercles de sélection sous les unités
  const selSet = new Set(G.selection);
  for (const u of G.units) {
    if (!inView(u) || !selSet.has(u)) continue;
    ctx.strokeStyle = u.team === PLAYER ? '#4ade80' : '#f87171';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.ellipse(u.x, u.y + u.radius * 0.5, u.radius + 4, (u.radius + 4) * 0.6, 0, 0, Math.PI * 2);
    ctx.stroke();
  }

  // Effets de mort
  for (const e of G.effects) {
    if (e.type !== 'death') continue;
    const k = e.t / e.life;
    ctx.globalAlpha = 1 - k;
    ctx.fillStyle = TEAM_DARK[e.team];
    ctx.beginPath(); ctx.ellipse(e.x, e.y + 3, e.r * (1 + k * 0.4), e.r * 0.5, 0, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
  }

  // Unités
  const sorted = G.units.filter(u => inView(u) && isVisibleToPlayer(u)).sort((a, b) => a.y - b.y);
  for (const u of sorted) drawUnit(ctx, u, selSet.has(u), ui.hover === u);

  // Projectiles
  for (const p of G.projectiles) {
    if (!isPointVisible(p.x, p.y)) continue;
    const k = Math.min(1, p.t / p.dur);
    if (p.kind === 'arrow') {
      const a = Math.atan2(p.ty - p.sy, p.tx - p.sx);
      ctx.strokeStyle = '#f5e6c8';
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(p.x - Math.cos(a) * 8, p.y - Math.sin(a) * 8);
      ctx.lineTo(p.x, p.y);
      ctx.stroke();
    } else {
      const h = Math.sin(k * Math.PI) * 60;
      ctx.fillStyle = 'rgba(0,0,0,0.3)';
      ctx.beginPath(); ctx.ellipse(p.x, p.y, 5, 3, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = '#78716c';
      ctx.beginPath(); ctx.arc(p.x, p.y - h, 5, 0, Math.PI * 2); ctx.fill();
    }
  }

  // Explosions
  for (const e of G.effects) {
    if (e.type !== 'explosion' || !isPointVisible(e.x, e.y)) continue;
    const k = e.t / e.life;
    ctx.globalAlpha = 1 - k;
    ctx.fillStyle = '#fb923c';
    ctx.beginPath(); ctx.arc(e.x, e.y, e.r * (0.4 + k * 0.6), 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = '#78350f';
    ctx.beginPath(); ctx.arc(e.x, e.y, e.r * 0.3 * (1 - k), 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
  }

  // Brouillard
  updateFogCanvas();
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(fogCanvas, 0, 0, WORLD_W, WORLD_H);

  // Marqueurs d'ordre
  for (const m of ui.markers) {
    const k = m.t / 0.6;
    ctx.strokeStyle = m.color;
    ctx.globalAlpha = 1 - k;
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.ellipse(m.x, m.y, 14 * (1 - k * 0.5), 8 * (1 - k * 0.5), 0, 0, Math.PI * 2); ctx.stroke();
    ctx.globalAlpha = 1;
  }

  // Points de ralliement
  for (const b of G.selection) {
    if (b.kind !== 'building' || !b.rally || b.team !== PLAYER) continue;
    ctx.strokeStyle = 'rgba(255,255,255,0.4)';
    ctx.setLineDash([6, 6]);
    ctx.beginPath(); ctx.moveTo(b.x, b.y); ctx.lineTo(b.rally.x, b.rally.y); ctx.stroke();
    ctx.setLineDash([]);
    ctx.fillStyle = TEAM_COLORS[PLAYER];
    ctx.fillRect(b.rally.x, b.rally.y - 18, 12, 8);
    ctx.fillStyle = '#ddd';
    ctx.fillRect(b.rally.x - 1, b.rally.y - 18, 2, 18);
  }

  // Aperçu de placement de bâtiment
  if (ui.placing) {
    const def = BUILDING_TYPES[ui.placing];
    const ok = canPlaceBuilding(ui.placing, ui.placeTx, ui.placeTy, PLAYER);
    ctx.fillStyle = ok ? 'rgba(74,222,128,0.35)' : 'rgba(248,113,113,0.4)';
    ctx.strokeStyle = ok ? '#4ade80' : '#f87171';
    ctx.lineWidth = 2;
    ctx.fillRect(ui.placeTx * TILE, ui.placeTy * TILE, def.w * TILE, def.h * TILE);
    ctx.strokeRect(ui.placeTx * TILE, ui.placeTy * TILE, def.w * TILE, def.h * TILE);
    if (def.range) {
      ctx.setLineDash([4, 6]);
      ctx.beginPath();
      ctx.arc((ui.placeTx + def.w / 2) * TILE, (ui.placeTy + def.h / 2) * TILE, def.range, 0, Math.PI * 2);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  // Rectangle de sélection
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  if (ui.drag && ui.drag.active) {
    const d = ui.drag;
    ctx.strokeStyle = '#4ade80';
    ctx.fillStyle = 'rgba(74,222,128,0.1)';
    ctx.lineWidth = 1;
    const x = Math.min(d.sx, d.cx), y = Math.min(d.sy, d.cy);
    ctx.fillRect(x, y, Math.abs(d.cx - d.sx), Math.abs(d.cy - d.sy));
    ctx.strokeRect(x, y, Math.abs(d.cx - d.sx), Math.abs(d.cy - d.sy));
  }
}

function isPointVisible(x, y) {
  const tx = Math.floor(x / TILE), ty = Math.floor(y / TILE);
  return inMap(tx, ty) && G.visible[tileIdx(tx, ty)] === 1;
}

function drawHealthBar(ctx, x, y, w, frac, color) {
  ctx.fillStyle = 'rgba(0,0,0,0.7)';
  ctx.fillRect(x - w / 2 - 1, y - 1, w + 2, 5);
  ctx.fillStyle = color || (frac > 0.6 ? '#4ade80' : frac > 0.3 ? '#facc15' : '#ef4444');
  ctx.fillRect(x - w / 2, y, w * Math.max(0, frac), 3);
}

function drawUnit(ctx, u, selected, hovered) {
  const col = TEAM_COLORS[u.team], dark = TEAM_DARK[u.team], light = TEAM_LIGHT[u.team];
  const r = u.radius;
  const fx = Math.cos(u.facing), fy = Math.sin(u.facing);
  const lunge = u.attackAnim > 0 ? 3 : 0;

  // Ombre
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.beginPath(); ctx.ellipse(u.x + 2, u.y + r * 0.6, r, r * 0.45, 0, 0, Math.PI * 2); ctx.fill();

  ctx.save();
  ctx.translate(u.x, u.y);

  switch (u.type) {
    case 'knight': {
      // Cheval
      ctx.save();
      ctx.rotate(u.facing);
      ctx.fillStyle = '#6b4f35';
      ctx.beginPath(); ctx.ellipse(0, 0, r + 2, r * 0.6, 0, 0, Math.PI * 2); ctx.fill();
      ctx.beginPath(); ctx.ellipse(r + 2, 0, 5, 4, 0, 0, Math.PI * 2); ctx.fill();
      ctx.restore();
      ctx.fillStyle = col; ctx.strokeStyle = dark; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(0, -3, r * 0.6, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      ctx.strokeStyle = '#e5e7eb'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(fx * 2, -3 + fy * 2); ctx.lineTo(fx * (r + 10 + lunge), -3 + fy * (r + 10 + lunge)); ctx.stroke();
      break;
    }
    case 'catapult': {
      ctx.save();
      ctx.rotate(u.facing);
      ctx.fillStyle = '#7c5a3a'; ctx.strokeStyle = '#3f2d1c'; ctx.lineWidth = 2;
      ctx.fillRect(-r, -r * 0.7, r * 2, r * 1.4); ctx.strokeRect(-r, -r * 0.7, r * 2, r * 1.4);
      ctx.fillStyle = '#222';
      for (const [wx, wy] of [[-r * 0.6, -r * 0.8], [r * 0.6, -r * 0.8], [-r * 0.6, r * 0.8], [r * 0.6, r * 0.8]]) {
        ctx.beginPath(); ctx.arc(wx, wy, 3.5, 0, Math.PI * 2); ctx.fill();
      }
      const arm = u.attackAnim > 0 ? r : -r * 0.8;
      ctx.strokeStyle = '#a07850'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(arm, 0); ctx.stroke();
      ctx.fillStyle = col;
      ctx.fillRect(-4, -4, 8, 8);
      ctx.restore();
      break;
    }
    default: {
      // Fantassin
      ctx.fillStyle = col; ctx.strokeStyle = dark; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
      ctx.fillStyle = light;
      ctx.beginPath(); ctx.arc(-r * 0.3, -r * 0.3, r * 0.35, 0, Math.PI * 2); ctx.fill();
      if (u.type === 'spearman') {
        ctx.strokeStyle = '#d6c7a1'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(-fx * 6, -fy * 6); ctx.lineTo(fx * (r + 12 + lunge * 2), fy * (r + 12 + lunge * 2)); ctx.stroke();
        ctx.fillStyle = '#e5e7eb';
        ctx.beginPath(); ctx.arc(fx * (r + 12 + lunge * 2), fy * (r + 12 + lunge * 2), 2.5, 0, Math.PI * 2); ctx.fill();
        // bouclier
        ctx.fillStyle = dark;
        ctx.beginPath(); ctx.arc(-fy * r * 0.8, fx * r * 0.8, 4.5, 0, Math.PI * 2); ctx.fill();
      } else if (u.type === 'archer') {
        ctx.strokeStyle = '#8b5a2b'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.arc(fx * 4, fy * 4, r + 2, u.facing - 1.1, u.facing + 1.1); ctx.stroke();
        ctx.strokeStyle = 'rgba(255,255,255,0.6)'; ctx.lineWidth = 1;
        const a1 = u.facing - 1.1, a2 = u.facing + 1.1;
        ctx.beginPath();
        ctx.moveTo(fx * 4 + Math.cos(a1) * (r + 2), fy * 4 + Math.sin(a1) * (r + 2));
        ctx.lineTo(fx * 4 + Math.cos(a2) * (r + 2), fy * 4 + Math.sin(a2) * (r + 2));
        ctx.stroke();
      } else if (u.type === 'worker') {
        const swing = u.attackAnim > 0 ? 0.8 : 0;
        const a = u.facing - 0.6 + swing;
        ctx.strokeStyle = '#8b5a2b'; ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(Math.cos(a) * (r + 7), Math.sin(a) * (r + 7)); ctx.stroke();
        ctx.strokeStyle = '#9ca3af'; ctx.lineWidth = 3;
        const hx = Math.cos(a) * (r + 7), hy = Math.sin(a) * (r + 7);
        ctx.beginPath(); ctx.moveTo(hx - Math.sin(a) * 4, hy + Math.cos(a) * 4); ctx.lineTo(hx + Math.sin(a) * 4, hy - Math.cos(a) * 4); ctx.stroke();
        if (u.carry > 0) {
          ctx.fillStyle = '#facc15'; ctx.strokeStyle = '#a16207'; ctx.lineWidth = 1;
          ctx.beginPath(); ctx.arc(-fx * 6, -fy * 6 - 4, 4, 0, Math.PI * 2); ctx.fill(); ctx.stroke();
        }
      }
    }
  }
  ctx.restore();

  if (selected || hovered || u.hp < u.maxHp) {
    drawHealthBar(ctx, u.x, u.y - r - 9, r * 2 + 4, u.hp / u.maxHp);
  }
}

function drawMine(ctx, m) {
  const x = m.tx * TILE, y = m.ty * TILE, w = m.tw * TILE, h = m.th * TILE;
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.beginPath(); ctx.ellipse(m.x + 3, m.y + 6, w / 2, h / 2.4, 0, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#6b6259';
  ctx.beginPath();
  ctx.moveTo(x + 4, y + h - 4); ctx.lineTo(x + 8, y + 14); ctx.lineTo(x + 22, y + 3);
  ctx.lineTo(x + 44, y + 8); ctx.lineTo(x + w - 3, y + 30); ctx.lineTo(x + w - 6, y + h - 4);
  ctx.closePath(); ctx.fill();
  ctx.strokeStyle = '#3f3a35'; ctx.lineWidth = 2; ctx.stroke();
  ctx.fillStyle = '#1c1917';
  ctx.beginPath(); ctx.arc(m.x, m.y + 10, 9, Math.PI, 0); ctx.lineTo(m.x + 9, m.y + 22); ctx.lineTo(m.x - 9, m.y + 22); ctx.fill();
  const frac = m.gold / m.maxGold;
  ctx.fillStyle = '#facc15';
  const nuggets = [[14, 16], [40, 18], [26, 12], [48, 34], [12, 40], [34, 26]];
  for (let i = 0; i < Math.ceil(frac * nuggets.length); i++) {
    const [nx, ny] = nuggets[i];
    ctx.beginPath(); ctx.arc(x + nx, y + ny, 3, 0, Math.PI * 2); ctx.fill();
  }
}

function drawBuilding(ctx, b, ui) {
  const x = b.tx * TILE, y = b.ty * TILE, w = b.tw * TILE, h = b.th * TILE;
  const col = TEAM_COLORS[b.team], dark = TEAM_DARK[b.team];
  const selected = G.selection.includes(b);

  ctx.fillStyle = 'rgba(0,0,0,0.35)';
  ctx.fillRect(x + 6, y + 8, w - 4, h - 4);

  if (!b.complete) {
    // Chantier
    ctx.fillStyle = '#8b7355';
    ctx.fillRect(x + 3, y + 3, w - 6, h - 6);
    ctx.strokeStyle = '#5c4a35'; ctx.lineWidth = 2;
    for (let i = 0; i < w + h; i += 12) {
      ctx.beginPath();
      ctx.moveTo(x + 3 + Math.min(i, w - 6), y + 3 + Math.max(0, i - (w - 6)));
      ctx.lineTo(x + 3 + Math.max(0, i - (h - 6)), y + 3 + Math.min(i, h - 6));
      ctx.stroke();
    }
    ctx.globalAlpha = 0.35 + b.progress * 0.65;
    drawBuildingBody(ctx, b, x, y, w, h, col, dark, b.progress);
    ctx.globalAlpha = 1;
    drawHealthBar(ctx, b.x, y + h + 3, w - 8, b.progress, '#38bdf8');
  } else {
    drawBuildingBody(ctx, b, x, y, w, h, col, dark, 1);
  }

  if (selected) {
    ctx.strokeStyle = b.team === PLAYER ? '#4ade80' : '#f87171';
    ctx.lineWidth = 2;
    ctx.strokeRect(x - 2, y - 2, w + 4, h + 4);
    if (b.def.range) {
      ctx.setLineDash([4, 6]);
      ctx.beginPath(); ctx.arc(b.x, b.y, b.def.range, 0, Math.PI * 2); ctx.stroke();
      ctx.setLineDash([]);
    }
  }
  if (selected || ui.hover === b || b.hp < b.maxHp) drawHealthBar(ctx, b.x, y - 8, w - 8, b.hp / b.maxHp);
  if (b.complete && b.queue.length && b.team === PLAYER) {
    const it = b.queue[0];
    drawHealthBar(ctx, b.x, y + h + 3, w - 8, it.t / UNIT_TYPES[it.type].time, '#e2e8f0');
  }
}

function drawBuildingBody(ctx, b, x, y, w, h, col, dark, prog) {
  const inset = 4;
  const bx = x + inset, by = y + inset, bw = w - inset * 2, bh = h - inset * 2;
  switch (b.type) {
    case 'hq': {
      ctx.fillStyle = '#a8a29e'; ctx.fillRect(bx, by + 10, bw, bh - 10);
      ctx.strokeStyle = '#57534e'; ctx.lineWidth = 2; ctx.strokeRect(bx, by + 10, bw, bh - 10);
      // tours d'angle
      ctx.fillStyle = '#78716c';
      for (const [cx, cy] of [[bx, by + 8], [bx + bw - 16, by + 8], [bx, by + bh - 16], [bx + bw - 16, by + bh - 16]]) {
        ctx.fillRect(cx, cy, 16, 16);
        ctx.fillStyle = col; ctx.fillRect(cx + 3, cy + 3, 10, 10); ctx.fillStyle = '#78716c';
      }
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.moveTo(b.x - 20, b.y); ctx.lineTo(b.x, b.y - 26); ctx.lineTo(b.x + 20, b.y); ctx.fill();
      ctx.fillStyle = dark; ctx.fillRect(b.x - 16, b.y, 32, 20);
      ctx.fillStyle = '#292524'; ctx.fillRect(b.x - 6, b.y + 8, 12, 12);
      // drapeau
      ctx.fillStyle = '#e7e5e4'; ctx.fillRect(b.x - 1, b.y - 44, 2, 20);
      ctx.fillStyle = col; ctx.fillRect(b.x + 1, b.y - 44, 14, 9);
      break;
    }
    case 'house': {
      ctx.fillStyle = '#d6c7a1'; ctx.fillRect(bx + 4, by + 18, bw - 8, bh - 18);
      ctx.strokeStyle = '#7c6a4a'; ctx.lineWidth = 2; ctx.strokeRect(bx + 4, by + 18, bw - 8, bh - 18);
      ctx.fillStyle = col;
      ctx.beginPath(); ctx.moveTo(bx, by + 20); ctx.lineTo(b.x, by); ctx.lineTo(bx + bw, by + 20); ctx.closePath(); ctx.fill();
      ctx.strokeStyle = dark; ctx.stroke();
      ctx.fillStyle = '#5c4a35'; ctx.fillRect(b.x - 5, by + bh - 14, 10, 14);
      break;
    }
    case 'barracks':
    case 'stable':
    case 'workshop': {
      const wall = b.type === 'barracks' ? '#8d7b68' : b.type === 'stable' ? '#9a7b4f' : '#6b7280';
      ctx.fillStyle = wall; ctx.fillRect(bx, by + 14, bw, bh - 14);
      ctx.strokeStyle = 'rgba(0,0,0,0.5)'; ctx.lineWidth = 2; ctx.strokeRect(bx, by + 14, bw, bh - 14);
      ctx.fillStyle = col;
      ctx.fillRect(bx - 2, by + 4, bw + 4, 14);
      ctx.fillStyle = dark; ctx.fillRect(bx - 2, by + 16, bw + 4, 3);
      ctx.fillStyle = '#292524'; ctx.fillRect(b.x - 10, by + bh - 20, 20, 20);
      // emblème
      ctx.save(); ctx.translate(b.x, by + 40); ctx.strokeStyle = '#f5f5f4'; ctx.fillStyle = '#f5f5f4'; ctx.lineWidth = 2.5;
      if (b.type === 'barracks') {
        ctx.beginPath(); ctx.moveTo(-10, -10); ctx.lineTo(10, 10); ctx.moveTo(10, -10); ctx.lineTo(-10, 10); ctx.stroke();
      } else if (b.type === 'stable') {
        ctx.beginPath(); ctx.arc(0, 0, 9, Math.PI * 0.15, Math.PI * 0.85, true); ctx.stroke();
      } else {
        ctx.beginPath(); ctx.arc(0, 0, 8, 0, Math.PI * 2); ctx.stroke();
        ctx.beginPath(); ctx.arc(0, 0, 3, 0, Math.PI * 2); ctx.fill();
      }
      ctx.restore();
      break;
    }
    case 'tower': {
      ctx.fillStyle = '#78716c'; ctx.beginPath(); ctx.arc(b.x, b.y + 4, bw / 2 - 2, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = '#44403c'; ctx.lineWidth = 2; ctx.stroke();
      ctx.fillStyle = '#a8a29e'; ctx.beginPath(); ctx.arc(b.x, b.y - 2, bw / 2 - 8, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = col; ctx.beginPath(); ctx.arc(b.x, b.y - 2, bw / 2 - 16, 0, Math.PI * 2); ctx.fill();
      for (let i = 0; i < 8; i++) {
        const a = i / 8 * Math.PI * 2;
        ctx.fillStyle = '#57534e';
        ctx.fillRect(b.x + Math.cos(a) * (bw / 2 - 6) - 3, b.y - 2 + Math.sin(a) * (bw / 2 - 6) - 3, 6, 6);
      }
      break;
    }
  }
}

// Mini-carte ------------------------------------------------------------------

let minimapTerrain = null;

function renderMinimap(mctx, mw, mh, viewW, viewH) {
  const sx = mw / WORLD_W, sy = mh / WORLD_H;
  if (!minimapTerrain) {
    minimapTerrain = document.createElement('canvas');
    minimapTerrain.width = mw; minimapTerrain.height = mh;
    minimapTerrain.getContext('2d').drawImage(terrainCanvas, 0, 0, mw, mh);
  }
  mctx.imageSmoothingEnabled = true;
  mctx.drawImage(minimapTerrain, 0, 0);
  for (const m of G.mines) {
    if (!G.explored[tileIdx(m.tx, m.ty)]) continue;
    mctx.fillStyle = '#facc15';
    mctx.fillRect(m.tx * TILE * sx, m.ty * TILE * sy, Math.max(3, m.tw * TILE * sx), Math.max(3, m.th * TILE * sy));
  }
  for (const b of G.buildings) {
    if (b.team !== PLAYER && !b.seen) continue;
    mctx.fillStyle = TEAM_COLORS[b.team];
    mctx.fillRect(b.tx * TILE * sx, b.ty * TILE * sy, Math.max(4, b.tw * TILE * sx), Math.max(4, b.th * TILE * sy));
  }
  for (const u of G.units) {
    if (!isVisibleToPlayer(u)) continue;
    mctx.fillStyle = u.team === PLAYER ? TEAM_LIGHT[PLAYER] : TEAM_COLORS[ENEMY];
    mctx.fillRect(u.x * sx - 1.5, u.y * sy - 1.5, 3, 3);
  }
  mctx.drawImage(fogCanvas, 0, 0, mw, mh);
  if (G.attackAlertTimer > 9 && G.lastAlert) {
    mctx.strokeStyle = '#ef4444'; mctx.lineWidth = 2;
    const r = 6 + (12 - G.attackAlertTimer) * 10;
    mctx.beginPath(); mctx.arc(G.lastAlert.x * sx, G.lastAlert.y * sy, r, 0, Math.PI * 2); mctx.stroke();
  }
  mctx.strokeStyle = '#fff'; mctx.lineWidth = 1;
  mctx.strokeRect(cam.x * sx, cam.y * sy, viewW / cam.zoom * sx, viewH / cam.zoom * sy);
}
