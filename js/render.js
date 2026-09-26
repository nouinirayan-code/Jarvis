'use strict';

// ---------------------------------------------------------------------------
// Rendu : décor, personnages, éclairage dynamique
// ---------------------------------------------------------------------------

const cam = { x: 0, y: 0, zoom: 1, shake: 0 };
let groundCanvas = null;
let lightCanvas = null, lightCtx = null;

function buildGround() {
  groundCanvas = document.createElement('canvas');
  groundCanvas.width = WORLD_W;
  groundCanvas.height = WORLD_H;
  const c = groundCanvas.getContext('2d');
  const rng = mulberry32(G.seed ^ 0x9e3779b9);
  for (let ty = 0; ty < MAP_H; ty++) {
    for (let tx = 0; tx < MAP_W; tx++) {
      const x = tx * TILE, y = ty * TILE;
      const n = rng();
      if (G.terrain[idx(tx, ty)] === T_WATER) {
        c.fillStyle = `hsl(215, 45%, ${16 + n * 4}%)`;
        c.fillRect(x, y, TILE, TILE);
        c.strokeStyle = 'rgba(160,190,255,0.12)';
        c.beginPath(); const wy = y + 10 + rng() * 20; c.moveTo(x + 6, wy); c.quadraticCurveTo(x + 14, wy - 4, x + 22, wy); c.stroke();
      } else {
        c.fillStyle = `hsl(${104 + n * 8}, ${30 + n * 5}%, ${25 + n * 3}%)`;
        c.fillRect(x, y, TILE, TILE);
        for (let k = 0; k < 5; k++) {
          c.fillStyle = rng() < 0.5 ? 'rgba(200,230,150,0.06)' : 'rgba(0,30,0,0.12)';
          c.fillRect(x + rng() * TILE, y + rng() * TILE, 2, 3 + rng() * 4);
        }
        if (rng() < 0.05) {
          c.fillStyle = ['#fde68a', '#c4b5fd', '#fca5a5'][Math.floor(rng() * 3)];
          c.beginPath(); c.arc(x + rng() * TILE, y + rng() * TILE, 2, 0, Math.PI * 2); c.fill();
        }
      }
    }
  }
  // Berges
  for (let ty = 0; ty < MAP_H; ty++) {
    for (let tx = 0; tx < MAP_W; tx++) {
      if (G.terrain[idx(tx, ty)] !== T_WATER) continue;
      for (const [ox, oy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = tx + ox, ny = ty + oy;
        if (!inMap(nx, ny) || G.terrain[idx(nx, ny)] === T_WATER) continue;
        c.fillStyle = 'rgba(120,100,60,0.55)';
        const x = tx * TILE, y = ty * TILE;
        if (ox === 1) c.fillRect(x + TILE - 4, y, 4, TILE);
        if (ox === -1) c.fillRect(x, y, 4, TILE);
        if (oy === 1) c.fillRect(x, y + TILE - 4, TILE, 4);
        if (oy === -1) c.fillRect(x, y, TILE, 4);
      }
    }
  }
  // Dalles autour du foyer
  for (let a = 0; a < 18; a++) {
    const ang = a / 18 * Math.PI * 2;
    const x = HEARTH_X + Math.cos(ang) * 70, y = HEARTH_Y + Math.sin(ang) * 70;
    c.fillStyle = 'rgba(120,113,108,0.5)';
    c.beginPath(); c.ellipse(x, y, 14, 10, ang, 0, Math.PI * 2); c.fill();
  }
}

function worldToScreen(x, y) { return { x: (x - cam.x) * cam.zoom, y: (y - cam.y) * cam.zoom }; }
function screenToWorld(x, y) { return { x: x / cam.zoom + cam.x, y: y / cam.zoom + cam.y }; }

function updateCamera(dt, W, H) {
  const p = G.player;
  const tx = (p.downT > 0 ? HEARTH_X : p.x) - W / 2 / cam.zoom;
  const ty = (p.downT > 0 ? HEARTH_Y : p.y) - H / 2 / cam.zoom;
  const k = Math.min(1, dt * 6);
  cam.x += (tx - cam.x) * k;
  cam.y += (ty - cam.y) * k;
  cam.x = Math.max(0, Math.min(WORLD_W - W / cam.zoom, cam.x));
  cam.y = Math.max(0, Math.min(WORLD_H - H / cam.zoom, cam.y));
  cam.shake = Math.max(0, cam.shake - dt * 20);
}

function render(ctx, W, H, dpr) {
  const z = cam.zoom * dpr;
  const sx = (Math.random() - 0.5) * cam.shake, sy = (Math.random() - 0.5) * cam.shake;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = '#05060c';
  ctx.fillRect(0, 0, W, H);
  ctx.setTransform(z, 0, 0, z, (-cam.x + sx) * z, (-cam.y + sy) * z);
  ctx.drawImage(groundCanvas, 0, 0);

  const vx0 = cam.x - 80, vy0 = cam.y - 80, vx1 = cam.x + W / cam.zoom + 80, vy1 = cam.y + H / cam.zoom + 80;
  const inView = e => e.x > vx0 && e.x < vx1 && e.y > vy0 && e.y < vy1;
  const t = G.time;

  // Objets au sol
  for (const b of G.buildings) if (b.type === 'spikes' && inView(b)) drawBuilding(ctx, b, t);
  for (const k of G.pickups) {
    if (!inView(k)) continue;
    const s = 4 + Math.sin(t * 8 + k.x) * 1;
    ctx.fillStyle = '#fb923c';
    ctx.beginPath(); ctx.moveTo(k.x, k.y - s - 2); ctx.lineTo(k.x + s, k.y); ctx.lineTo(k.x, k.y + s + 2); ctx.lineTo(k.x - s, k.y); ctx.fill();
  }

  // Tri par profondeur
  const items = [];
  for (const n of G.nodes) if (inView(n)) items.push(n);
  for (const b of G.buildings) if (b.type !== 'spikes' && inView(b)) items.push(b);
  for (const e of G.enemies) if (inView(e)) items.push(e);
  items.push(G.hearth);
  if (G.player.downT <= 0) items.push(G.player);
  items.sort((a, b) => a.y - b.y);
  for (const it of items) {
    if (it === G.player) drawPlayer(ctx, it, t);
    else if (it.kind === 'node') drawNode(ctx, it, t);
    else if (it.kind === 'building') drawBuilding(ctx, it, t);
    else if (it.kind === 'hearth') drawHearth(ctx, it, t);
    else drawEnemy(ctx, it, t);
  }

  // Projectiles et particules
  for (const pr of G.projectiles) {
    if (!inView(pr)) continue;
    if (pr.from === 'tower') {
      const a = Math.atan2(pr.vy, pr.vx);
      ctx.strokeStyle = '#e7e5e4'; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.moveTo(pr.x - Math.cos(a) * 14, pr.y - Math.sin(a) * 14); ctx.lineTo(pr.x, pr.y); ctx.stroke();
    } else {
      ctx.fillStyle = pr.color;
      ctx.beginPath(); ctx.arc(pr.x, pr.y, pr.r, 0, Math.PI * 2); ctx.fill();
    }
  }
  for (const p of G.particles) {
    if (!inView(p)) continue;
    ctx.globalAlpha = 1 - p.t / p.life;
    ctx.fillStyle = p.color;
    ctx.fillRect(p.x - p.size / 2, p.y - p.size / 2, p.size, p.size);
  }
  ctx.globalAlpha = 1;

  // Éclairage
  drawLighting(ctx, W, H, dpr, t);

  // Au-dessus des ténèbres : yeux des ombres, braises, textes
  ctx.setTransform(z, 0, 0, z, (-cam.x + sx) * z, (-cam.y + sy) * z);
  for (const e of G.enemies) if (inView(e)) drawEnemyEyes(ctx, e, t);
  for (const k of G.pickups) {
    if (!inView(k)) continue;
    ctx.fillStyle = 'rgba(251,146,60,0.9)';
    ctx.beginPath(); ctx.arc(k.x, k.y, 2.5, 0, Math.PI * 2); ctx.fill();
  }
  for (const pr of G.projectiles) {
    if (pr.from !== 'enemy' || !inView(pr)) continue;
    ctx.fillStyle = pr.color; ctx.globalAlpha = 0.8;
    ctx.beginPath(); ctx.arc(pr.x, pr.y, pr.r * 0.7, 0, Math.PI * 2); ctx.fill();
    ctx.globalAlpha = 1;
  }
  drawBuildGhost(ctx);
  for (const f of G.floaters) {
    const k = f.t / 1.2;
    ctx.globalAlpha = 1 - k;
    ctx.font = 'bold 14px Georgia, serif';
    ctx.textAlign = 'center';
    ctx.fillStyle = '#000';
    ctx.fillText(f.text, f.x + 1, f.y - k * 30 + 1);
    ctx.fillStyle = f.color;
    ctx.fillText(f.text, f.x, f.y - k * 30);
  }
  ctx.globalAlpha = 1;
  ctx.textAlign = 'start';
}

function drawLighting(ctx, W, H, dpr, t) {
  const dark = darkness();
  if (!lightCanvas || lightCanvas.width !== Math.ceil(W / 2) || lightCanvas.height !== Math.ceil(H / 2)) {
    // Résolution réduite : les dégradés restent doux et c'est plus rapide
    lightCanvas = document.createElement('canvas');
    lightCanvas.width = Math.ceil(W / 2);
    lightCanvas.height = Math.ceil(H / 2);
    lightCtx = lightCanvas.getContext('2d');
  }
  const L = lightCtx;
  const s = cam.zoom / 2;
  L.setTransform(1, 0, 0, 1, 0, 0);
  L.globalCompositeOperation = 'source-over';
  L.clearRect(0, 0, lightCanvas.width, lightCanvas.height);
  L.fillStyle = `rgba(3,4,14,${dark})`;
  L.fillRect(0, 0, lightCanvas.width, lightCanvas.height);
  L.globalCompositeOperation = 'destination-out';
  const hole = (x, y, r, strength) => {
    const px = (x - cam.x) * s, py = (y - cam.y) * s, pr = r * s;
    if (px + pr < 0 || py + pr < 0 || px - pr > lightCanvas.width || py - pr > lightCanvas.height) return;
    const g = L.createRadialGradient(px, py, pr * 0.15, px, py, pr);
    g.addColorStop(0, `rgba(0,0,0,${strength})`);
    g.addColorStop(0.6, `rgba(0,0,0,${strength * 0.75})`);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    L.fillStyle = g;
    L.beginPath(); L.arc(px, py, pr, 0, Math.PI * 2); L.fill();
  };
  const flick = 1 + Math.sin(t * 11) * 0.02 + Math.sin(t * 23) * 0.015;
  for (const l of G.lights) hole(l.x, l.y, l.r * flick * 1.12, 1);
  const p = G.player;
  if (p.downT <= 0) hole(p.x, p.y, playerLanternRadius() * flick, 0.95);
  for (const n of G.nodes) if (n.type === 'crystal') hole(n.x, n.y, 60, 0.7);
  for (const k of G.pickups) hole(k.x, k.y, 26, 0.6);

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.imageSmoothingEnabled = true;
  ctx.drawImage(lightCanvas, 0, 0, W, H);

  // Teinte chaude des flammes
  ctx.globalCompositeOperation = 'soft-light';
  const glow = (x, y, r, a) => {
    const q = worldToScreen(x, y);
    const g = ctx.createRadialGradient(q.x, q.y, 0, q.x, q.y, r * cam.zoom);
    g.addColorStop(0, `rgba(255,120,30,${a})`);
    g.addColorStop(0.7, `rgba(255,90,20,${a * 0.5})`);
    g.addColorStop(1, 'rgba(255,80,20,0)');
    ctx.fillStyle = g;
    ctx.fillRect(q.x - r * cam.zoom, q.y - r * cam.zoom, r * 2 * cam.zoom, r * 2 * cam.zoom);
  };
  const ga = 0.15 + dark * 0.6;
  for (const l of G.lights) glow(l.x, l.y, l.r * 1.05, ga * flick);
  if (p.downT <= 0) glow(p.x, p.y, playerLanternRadius() * 0.6, ga * 0.7);
  ctx.globalCompositeOperation = 'source-over';
}

// Personnages ----------------------------------------------------------------------

function drawPlayer(ctx, p, t) {
  const r = p.radius;
  const blink = p.invuln > 0 && p.dashT <= 0 && Math.floor(t * 20) % 2 === 0;
  ctx.fillStyle = 'rgba(0,0,0,0.35)';
  ctx.beginPath(); ctx.ellipse(p.x, p.y + r * 0.8, r, r * 0.4, 0, 0, Math.PI * 2); ctx.fill();
  if (blink) ctx.globalAlpha = 0.5;
  const bob = Math.sin(p.walkT * 12) * 1.5;
  const fx = Math.cos(p.facing), fy = Math.sin(p.facing);

  // Cape
  ctx.fillStyle = p.hitFlash > 0 ? '#fecaca' : '#7f1d1d';
  ctx.beginPath();
  ctx.moveTo(p.x - fy * r * 0.9, p.y + fx * r * 0.9 + bob);
  ctx.quadraticCurveTo(p.x - fx * r * 1.8, p.y - fy * r * 1.8 + 6 + bob, p.x + fy * r * 0.9, p.y - fx * r * 0.9 + bob);
  ctx.fill();
  // Corps
  ctx.fillStyle = p.hitFlash > 0 ? '#fff' : '#57534e';
  ctx.beginPath(); ctx.arc(p.x, p.y + bob, r * 0.85, 0, Math.PI * 2); ctx.fill();
  ctx.strokeStyle = '#1c1917'; ctx.lineWidth = 2; ctx.stroke();
  // Capuche
  ctx.fillStyle = '#3f3a36';
  ctx.beginPath(); ctx.arc(p.x - fx * 2, p.y - 4 + bob - fy * 2, r * 0.6, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = '#e9b996';
  ctx.beginPath(); ctx.arc(p.x + fx * 3, p.y - 4 + bob + fy * 3, r * 0.3, 0, Math.PI * 2); ctx.fill();

  // Lanterne (main gauche)
  const lx = p.x - fy * (r + 4) + fx * 4, ly = p.y + fx * (r + 4) + fy * 4 + bob;
  ctx.strokeStyle = '#78716c'; ctx.lineWidth = 1.5;
  ctx.strokeRect(lx - 4, ly - 5, 8, 10);
  ctx.fillStyle = p.oil > 0 ? '#fde047' : '#78350f';
  ctx.fillRect(lx - 3, ly - 4, 6, 8);

  // Épée
  const swing = p.swingT > 0 ? (1 - p.swingT / 0.2) : -1;
  const base = p.facing + (swing >= 0 ? -PLAYER_DEF.arc / 2 + swing * PLAYER_DEF.arc : 0.9);
  const sx = p.x + fy * (r - 4), sy = p.y - fx * (r - 4) + bob;
  ctx.strokeStyle = '#e5e7eb'; ctx.lineWidth = 3; ctx.lineCap = 'round';
  ctx.beginPath(); ctx.moveTo(sx + Math.cos(base) * 6, sy + Math.sin(base) * 6); ctx.lineTo(sx + Math.cos(base) * (r + 26), sy + Math.sin(base) * (r + 26)); ctx.stroke();
  ctx.strokeStyle = '#a16207'; ctx.lineWidth = 3;
  ctx.beginPath(); ctx.moveTo(sx + Math.cos(base) * 6 - Math.sin(base) * 5, sy + Math.sin(base) * 6 + Math.cos(base) * 5);
  ctx.lineTo(sx + Math.cos(base) * 6 + Math.sin(base) * 5, sy + Math.sin(base) * 6 - Math.cos(base) * 5); ctx.stroke();
  ctx.lineCap = 'butt';
  if (swing >= 0) {
    ctx.strokeStyle = `rgba(255,236,180,${0.5 * (1 - swing)})`; ctx.lineWidth = 10;
    ctx.beginPath(); ctx.arc(p.x, p.y, PLAYER_DEF.range - 8, p.facing - PLAYER_DEF.arc / 2, base); ctx.stroke();
  }
  ctx.globalAlpha = 1;
}

function drawEnemy(ctx, e, t) {
  const r = e.radius;
  const d = e.def;
  ctx.globalAlpha = e.fade;
  ctx.fillStyle = 'rgba(0,0,0,0.35)';
  ctx.beginPath(); ctx.ellipse(e.x, e.y + r * 0.8, r, r * 0.35, 0, 0, Math.PI * 2); ctx.fill();
  // Tentacules d'ombre
  const n = d.boss ? 12 : e.type === 'brute' ? 8 : 6;
  ctx.strokeStyle = d.color; ctx.lineWidth = d.boss ? 7 : 3;
  for (let i = 0; i < n; i++) {
    const a = i / n * Math.PI * 2 + Math.sin(e.wob * 2 + i) * 0.3;
    const len = r * (1.2 + Math.sin(e.wob * 5 + i * 1.7) * 0.25);
    ctx.beginPath(); ctx.moveTo(e.x, e.y);
    ctx.quadraticCurveTo(e.x + Math.cos(a + 0.5) * len * 0.7, e.y + Math.sin(a + 0.5) * len * 0.7, e.x + Math.cos(a) * len, e.y + Math.sin(a) * len);
    ctx.stroke();
  }
  // Corps
  const g = ctx.createRadialGradient(e.x - r * 0.3, e.y - r * 0.3, r * 0.1, e.x, e.y, r);
  g.addColorStop(0, e.hitFlash > 0 ? '#ffffff' : '#3b3561');
  g.addColorStop(1, e.hitFlash > 0 ? '#c4b5fd' : d.color);
  ctx.fillStyle = g;
  ctx.beginPath();
  for (let i = 0; i <= 16; i++) {
    const a = i / 16 * Math.PI * 2;
    const rr = r * (1 + Math.sin(e.wob * 4 + i * 1.3) * 0.08);
    const x = e.x + Math.cos(a) * rr, y = e.y + Math.sin(a) * rr * (e.type === 'stalker' ? 0.8 : 1);
    if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
  }
  ctx.fill();
  if (e.type === 'brute' || d.boss) {
    ctx.fillStyle = '#44403c';
    for (const s of [-1, 1]) {
      ctx.beginPath(); ctx.moveTo(e.x + s * r * 0.4, e.y - r * 0.7); ctx.lineTo(e.x + s * r * 0.9, e.y - r * 1.4); ctx.lineTo(e.x + s * r * 0.7, e.y - r * 0.5); ctx.fill();
    }
  }
  if (e.hp < e.maxHp) {
    const w = d.boss ? 90 : r * 2.2;
    ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(e.x - w / 2 - 1, e.y - r - 12, w + 2, 5);
    ctx.fillStyle = d.boss ? '#dc2626' : '#a78bfa'; ctx.fillRect(e.x - w / 2, e.y - r - 11, w * Math.max(0, e.hp / e.maxHp), 3);
  }
  ctx.globalAlpha = 1;
}

function drawEnemyEyes(ctx, e, t) {
  const r = e.radius;
  const p = G.player;
  const a = Math.atan2(p.y - e.y, p.x - e.x);
  const ox = Math.cos(a) * r * 0.25, oy = Math.sin(a) * r * 0.25;
  const blink = Math.sin(e.wob * 1.7) > 0.97;
  if (blink) return;
  ctx.globalAlpha = e.fade;
  ctx.fillStyle = e.def.eye;
  ctx.shadowColor = e.def.eye; ctx.shadowBlur = 8;
  const eyes = e.def.boss ? [[-0.35, -0.2], [0.35, -0.2], [0, -0.45], [-0.15, 0.05], [0.15, 0.05]] : [[-0.3, -0.15], [0.3, -0.15]];
  for (const [ex, ey] of eyes) {
    ctx.beginPath(); ctx.ellipse(e.x + ex * r + ox, e.y + ey * r + oy, r * 0.13, r * 0.08, 0, 0, Math.PI * 2); ctx.fill();
  }
  if (e.def.boss) {
    ctx.fillStyle = '#7f1d1d';
    ctx.beginPath(); ctx.ellipse(e.x + ox, e.y + r * 0.35 + oy, r * 0.4, r * 0.15 + Math.sin(t * 6) * 3, 0, 0, Math.PI * 2); ctx.fill();
  }
  ctx.shadowBlur = 0;
  ctx.globalAlpha = 1;
}

// Décor et constructions -------------------------------------------------------------

function drawNode(ctx, n, t) {
  const sh = n.shake > 0 ? Math.sin(t * 80) * 3 : 0;
  const x = n.x + sh, y = n.y;
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.beginPath(); ctx.ellipse(n.x + 4, n.y + 12, 16, 7, 0, 0, Math.PI * 2); ctx.fill();
  if (n.type === 'tree') {
    ctx.fillStyle = '#4a3222'; ctx.fillRect(x - 4, y - 2, 8, 16);
    const hue = 110 + n.variant * 40;
    const layers = [[0, -8, 20, 22], [-6, -16, 15, 28], [6, -18, 14, 32], [0, -26, 12, 36]];
    for (const [ox, oy, rr, l] of layers) {
      ctx.fillStyle = `hsl(${hue}, 40%, ${l - 8}%)`;
      ctx.beginPath(); ctx.arc(x + ox, y + oy, rr, 0, Math.PI * 2); ctx.fill();
    }
    ctx.fillStyle = 'rgba(255,255,255,0.06)';
    ctx.beginPath(); ctx.arc(x - 5, y - 30, 7, 0, Math.PI * 2); ctx.fill();
  } else if (n.type === 'rock') {
    ctx.fillStyle = '#6b6560';
    ctx.beginPath(); ctx.moveTo(x - 17, y + 10); ctx.lineTo(x - 13, y - 8); ctx.lineTo(x - 2, y - 15); ctx.lineTo(x + 12, y - 10); ctx.lineTo(x + 17, y + 6); ctx.lineTo(x + 6, y + 13); ctx.closePath(); ctx.fill();
    ctx.fillStyle = '#8b857e';
    ctx.beginPath(); ctx.moveTo(x - 11, y - 6); ctx.lineTo(x - 2, y - 13); ctx.lineTo(x + 8, y - 8); ctx.lineTo(x - 2, y - 2); ctx.closePath(); ctx.fill();
    ctx.strokeStyle = '#3f3a36'; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.moveTo(x - 2, y - 2); ctx.lineTo(x + 3, y + 9); ctx.stroke();
  } else {
    const pulse = 0.7 + Math.sin(t * 3 + n.variant * 6) * 0.3;
    ctx.fillStyle = `rgba(251,146,60,${0.25 * pulse})`;
    ctx.beginPath(); ctx.arc(x, y, 24, 0, Math.PI * 2); ctx.fill();
    for (const [ox, h, w] of [[-7, 20, 7], [5, 26, 8], [0, 14, 9], [10, 14, 5]]) {
      ctx.fillStyle = '#c2410c';
      ctx.beginPath(); ctx.moveTo(x + ox - w / 2, y + 10); ctx.lineTo(x + ox, y + 10 - h); ctx.lineTo(x + ox + w / 2, y + 10); ctx.fill();
      ctx.fillStyle = `rgba(253,224,71,${0.6 * pulse})`;
      ctx.beginPath(); ctx.moveTo(x + ox - w / 4, y + 8); ctx.lineTo(x + ox, y + 10 - h * 0.8); ctx.lineTo(x + ox + w / 4, y + 8); ctx.fill();
    }
  }
}

function drawFlame(ctx, x, y, s, t) {
  const f = Math.sin(t * 15 + x) * 0.15;
  ctx.fillStyle = '#ea580c';
  ctx.beginPath(); ctx.moveTo(x - s, y); ctx.quadraticCurveTo(x - s * 0.8, y - s * 1.6, x + f * s, y - s * (2.4 + f)); ctx.quadraticCurveTo(x + s * 0.8, y - s * 1.6, x + s, y); ctx.fill();
  ctx.fillStyle = '#fde047';
  ctx.beginPath(); ctx.moveTo(x - s * 0.5, y); ctx.quadraticCurveTo(x - s * 0.4, y - s, x - f * s, y - s * (1.5 - f)); ctx.quadraticCurveTo(x + s * 0.4, y - s, x + s * 0.5, y); ctx.fill();
}

function drawHearth(ctx, h, t) {
  const x = h.x, y = h.y;
  ctx.fillStyle = 'rgba(0,0,0,0.4)';
  ctx.beginPath(); ctx.ellipse(x + 3, y + 12, 40, 18, 0, 0, Math.PI * 2); ctx.fill();
  // Cercle de pierres
  for (let i = 0; i < 12; i++) {
    const a = i / 12 * Math.PI * 2;
    ctx.fillStyle = h.hitFlash > 0 ? '#fca5a5' : (i % 2 ? '#78716c' : '#8b857e');
    ctx.beginPath(); ctx.ellipse(x + Math.cos(a) * 30, y + Math.sin(a) * 22, 10, 8, a, 0, Math.PI * 2); ctx.fill();
  }
  ctx.fillStyle = '#292524';
  ctx.beginPath(); ctx.ellipse(x, y, 24, 16, 0, 0, Math.PI * 2); ctx.fill();
  // Bûches
  ctx.strokeStyle = '#57381f'; ctx.lineWidth = 6;
  ctx.beginPath(); ctx.moveTo(x - 16, y + 6); ctx.lineTo(x + 14, y - 6); ctx.moveTo(x - 14, y - 6); ctx.lineTo(x + 16, y + 6); ctx.stroke();
  // Flamme selon le combustible
  const s = 6 + (h.fuel / HEARTH.maxFuel) * 16;
  if (h.fuel > 0) {
    drawFlame(ctx, x - 8, y + 4, s * 0.6, t + 1);
    drawFlame(ctx, x + 8, y + 4, s * 0.6, t + 2);
    drawFlame(ctx, x, y + 6, s, t);
  }
}

function drawBuilding(ctx, b, t) {
  const x = b.x, y = b.y;
  const sc = 0.6 + 0.4 * b.built;
  ctx.save();
  ctx.translate(x, y); ctx.scale(sc, sc); ctx.translate(-x, -y);
  const flash = b.hitFlash > 0;
  switch (b.type) {
    case 'wall': {
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.fillRect(x - 18, y + 8, 38, 10);
      for (let i = 0; i < 4; i++) {
        const px = x - 15 + i * 10;
        ctx.fillStyle = flash ? '#fecaca' : (i % 2 ? '#8b5a2b' : '#7c4a1e');
        ctx.fillRect(px - 4, y - 16, 9, 30);
        ctx.beginPath(); ctx.moveTo(px - 4, y - 16); ctx.lineTo(px + 0.5, y - 24); ctx.lineTo(px + 5, y - 16); ctx.fill();
      }
      ctx.fillStyle = '#5c3a1a'; ctx.fillRect(x - 20, y - 6, 40, 4); ctx.fillRect(x - 20, y + 6, 40, 4);
      break;
    }
    case 'torch': {
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.beginPath(); ctx.ellipse(x + 2, y + 12, 8, 4, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = flash ? '#fecaca' : '#6b4423'; ctx.fillRect(x - 3, y - 18, 6, 32);
      ctx.fillStyle = '#44403c'; ctx.fillRect(x - 6, y - 22, 12, 6);
      drawFlame(ctx, x, y - 22, 6, t);
      break;
    }
    case 'spikes': {
      ctx.fillStyle = 'rgba(60,40,20,0.6)'; ctx.fillRect(x - 18, y - 18, 36, 36);
      ctx.fillStyle = flash ? '#fecaca' : '#a8a29e';
      for (let i = 0; i < 9; i++) {
        const px = x - 12 + (i % 3) * 12, py = y - 10 + Math.floor(i / 3) * 11;
        ctx.beginPath(); ctx.moveTo(px - 4, py + 4); ctx.lineTo(px, py - 6); ctx.lineTo(px + 4, py + 4); ctx.fill();
      }
      break;
    }
    case 'ballista': {
      ctx.fillStyle = 'rgba(0,0,0,0.3)'; ctx.beginPath(); ctx.ellipse(x + 3, y + 10, 20, 8, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = flash ? '#fecaca' : '#57534e'; ctx.fillRect(x - 16, y - 8, 32, 20);
      ctx.fillStyle = '#44403c'; ctx.fillRect(x - 16, y - 12, 32, 6);
      ctx.save(); ctx.translate(x, y - 6); ctx.rotate(b.aim);
      ctx.fillStyle = '#7c4a1e'; ctx.fillRect(-6, -3, 26, 6);
      ctx.strokeStyle = '#a16207'; ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(8, 0, 14, -1.3, 1.3); ctx.stroke();
      ctx.strokeStyle = '#e7e5e4'; ctx.lineWidth = 1;
      const pull = b.cd > b.def.cooldown * 0.6 ? 0 : 5;
      ctx.beginPath(); ctx.moveTo(8 + Math.cos(-1.3) * 14, Math.sin(-1.3) * 14); ctx.lineTo(2 - pull, 0); ctx.lineTo(8 + Math.cos(1.3) * 14, Math.sin(1.3) * 14); ctx.stroke();
      ctx.restore();
      break;
    }
    case 'beacon': {
      ctx.fillStyle = 'rgba(0,0,0,0.35)'; ctx.beginPath(); ctx.ellipse(x + 3, y + 14, 18, 7, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = flash ? '#fecaca' : '#8b857e';
      ctx.beginPath(); ctx.moveTo(x - 14, y + 14); ctx.lineTo(x - 9, y - 24); ctx.lineTo(x + 9, y - 24); ctx.lineTo(x + 14, y + 14); ctx.fill();
      ctx.fillStyle = '#57534e'; ctx.fillRect(x - 15, y - 30, 30, 7);
      drawFlame(ctx, x, y - 30, 10, t);
      break;
    }
  }
  ctx.restore();
  if (b.hp < b.maxHp && b.type !== 'spikes') {
    ctx.fillStyle = 'rgba(0,0,0,0.7)'; ctx.fillRect(x - 17, y - 34, 34, 5);
    ctx.fillStyle = b.hp / b.maxHp > 0.4 ? '#86efac' : '#f87171'; ctx.fillRect(x - 16, y - 33, 32 * b.hp / b.maxHp, 3);
  }
}

function drawBuildGhost(ctx) {
  if (!UI.buildType || !G) return;
  const w = screenToWorld(INPUT.screenX, INPUT.screenY);
  const tx = tileOf(w.x), ty = tileOf(w.y);
  const ok = canBuildAt(UI.buildType, tx, ty) && canAfford(BUILD_TYPES[UI.buildType].cost);
  ctx.fillStyle = ok ? 'rgba(134,239,172,0.3)' : 'rgba(248,113,113,0.35)';
  ctx.strokeStyle = ok ? '#86efac' : '#f87171';
  ctx.lineWidth = 2;
  ctx.fillRect(tx * TILE, ty * TILE, TILE, TILE);
  ctx.strokeRect(tx * TILE, ty * TILE, TILE, TILE);
  const def = BUILD_TYPES[UI.buildType];
  const r = def.light || def.range;
  if (r) {
    ctx.setLineDash([6, 8]);
    ctx.beginPath(); ctx.arc(tx * TILE + TILE / 2, ty * TILE + TILE / 2, r, 0, Math.PI * 2); ctx.stroke();
    ctx.setLineDash([]);
  }
}

// Mini-carte --------------------------------------------------------------------------

let miniBase = null;
function renderMinimap(mc, w, h) {
  const sx = w / WORLD_W, sy = h / WORLD_H;
  if (!miniBase) {
    miniBase = document.createElement('canvas');
    miniBase.width = w; miniBase.height = h;
    miniBase.getContext('2d').drawImage(groundCanvas, 0, 0, w, h);
  }
  mc.drawImage(miniBase, 0, 0);
  mc.fillStyle = `rgba(3,4,14,${0.35 + darkness() * 0.4})`;
  mc.fillRect(0, 0, w, h);
  for (const l of G.lights) {
    mc.fillStyle = 'rgba(251,146,60,0.25)';
    mc.beginPath(); mc.arc(l.x * sx, l.y * sy, l.r * sx, 0, Math.PI * 2); mc.fill();
  }
  for (const n of G.nodes) {
    if (n.type !== 'crystal') continue;
    mc.fillStyle = '#fb923c'; mc.fillRect(n.x * sx - 1, n.y * sy - 1, 2.5, 2.5);
  }
  for (const b of G.buildings) { mc.fillStyle = '#d6b77a'; mc.fillRect(b.x * sx - 1, b.y * sy - 1, 2, 2); }
  for (const e of G.enemies) {
    mc.fillStyle = e.def.boss ? '#ef4444' : '#c084fc';
    const s = e.def.boss ? 5 : 2.5;
    mc.fillRect(e.x * sx - s / 2, e.y * sy - s / 2, s, s);
  }
  mc.fillStyle = '#fde047';
  mc.beginPath(); mc.arc(HEARTH_X * sx, HEARTH_Y * sy, 3, 0, Math.PI * 2); mc.fill();
  const p = G.player;
  mc.fillStyle = '#fff';
  mc.beginPath(); mc.arc(p.x * sx, p.y * sy, 2.5, 0, Math.PI * 2); mc.fill();
}
