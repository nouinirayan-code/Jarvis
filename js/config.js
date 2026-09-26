'use strict';

// ---------------------------------------------------------------------------
// Dernière Lueur — configuration
// ---------------------------------------------------------------------------

const TILE = 40;
const MAP_W = 70;
const MAP_H = 70;
const WORLD_W = MAP_W * TILE;
const WORLD_H = MAP_H * TILE;

const DAY_LENGTH = 55;          // secondes de jour
const DUSK_LENGTH = 6;          // transition jour -> nuit
const NIGHT_BASE = 65;          // durée de la première nuit
const NIGHT_GROW = 5;           // chaque nuit dure un peu plus
const BOSS_EVERY = 5;           // un Dévoreur toutes les 5 nuits

const PLAYER_DEF = {
  hp: 100, speed: 190, radius: 14,
  dmg: 20, range: 62, arc: 1.9, cooldown: 0.36,
  dashSpeed: 620, dashTime: 0.17, dashCooldown: 1.1,
  lantern: 150, oil: 100, oilDrain: 2.2, coldDamage: 6,
};

const HEARTH = {
  hp: 600, fuel: 70, maxFuel: 100,
  baseRadius: 110, radiusPerFuel: 2.6,
  burnDay: 0.12, burnNight: 0.55,
  emberFuel: 14, woodFuel: 2,
};

// Ressources des objets du décor
const NODE_TYPES = {
  tree: { name: 'Arbre', res: 'wood', amount: 5, hp: 1, radius: 16 },
  rock: { name: 'Rocher', res: 'stone', amount: 4, hp: 1, radius: 17 },
  crystal: { name: 'Cristal de braise', res: 'ember', amount: 3, hp: 1, radius: 14 },
};

// Constructions
const BUILD_TYPES = {
  wall: {
    name: 'Palissade', key: '1', cost: { wood: 3 }, hp: 140, solid: true,
    desc: 'Bloque le passage des ombres. Elles devront la détruire.',
  },
  torch: {
    name: 'Torche', key: '2', cost: { wood: 2, stone: 1 }, hp: 50, solid: true, light: 115,
    desc: 'Éclaire les environs : les ombres y sont ralenties et vulnérables.',
  },
  spikes: {
    name: 'Pièges à pieux', key: '3', cost: { wood: 3, stone: 2 }, hp: 30, solid: false, dmg: 12,
    desc: 'Blesse les ombres qui marchent dessus. S\'use à chaque coup.',
  },
  ballista: {
    name: 'Baliste', key: '4', cost: { wood: 6, stone: 5 }, hp: 170, solid: true,
    range: 270, dmg: 17, cooldown: 1.0,
    desc: 'Tire automatiquement sur les ombres à portée.',
  },
  beacon: {
    name: 'Phare', key: '5', cost: { stone: 6, ember: 2 }, hp: 220, solid: true, light: 200,
    desc: 'Grande lumière qui repousse les ténèbres et réchauffe le héros.',
  },
};
const BUILD_ORDER = ['wall', 'torch', 'spikes', 'ballista', 'beacon'];

// Ombres
const ENEMY_TYPES = {
  shade: {
    name: 'Ombre', hp: 42, speed: 82, dmg: 8, radius: 13, cooldown: 1.0, embers: 1,
    color: '#1e1b3a', eye: '#a78bfa',
  },
  stalker: {
    name: 'Rôdeur', hp: 24, speed: 150, dmg: 6, radius: 10, cooldown: 0.8, embers: 1, huntsPlayer: true,
    color: '#0f172a', eye: '#f472b6',
  },
  brute: {
    name: 'Colosse', hp: 190, speed: 50, dmg: 24, radius: 21, cooldown: 1.6, embers: 4, siege: 2,
    color: '#27131f', eye: '#fb923c',
  },
  spitter: {
    name: 'Cracheur', hp: 36, speed: 72, dmg: 7, radius: 12, cooldown: 2.0, embers: 2, ranged: 230,
    color: '#0c2a26', eye: '#4ade80',
  },
  devourer: {
    name: 'Dévoreur', hp: 1600, speed: 62, dmg: 40, radius: 36, cooldown: 1.4, embers: 25, siege: 2, boss: true,
    color: '#1a0b1e', eye: '#ef4444',
  },
};

// Améliorations achetées au foyer avec des braises
const UPGRADES = {
  blade: { name: 'Lame ardente', desc: '+25 % de dégâts à l\'épée', base: 4, step: 3, max: 6 },
  heart: { name: 'Cœur vaillant', desc: '+25 points de vie max (et soin complet)', base: 4, step: 3, max: 6 },
  lantern: { name: 'Grande lanterne', desc: '+20 % de rayon et d\'huile pour la lanterne', base: 3, step: 3, max: 5 },
  swift: { name: 'Pas du vent', desc: '+8 % de vitesse, esquive plus fréquente', base: 3, step: 3, max: 5 },
  hearth: { name: 'Foyer de pierre', desc: '+150 PV au foyer et flamme plus économe', base: 5, step: 4, max: 5 },
};
