'use strict';

// ---------------------------------------------------------------------------
// Configuration générale du jeu
// ---------------------------------------------------------------------------
const TILE = 32;
const MAP_W = 96;
const MAP_H = 64;
const WORLD_W = MAP_W * TILE;
const WORLD_H = MAP_H * TILE;
const MAX_POP = 200;

const PLAYER = 0;
const ENEMY = 1;
const TEAM_COLORS = ['#3b82f6', '#ef4444'];
const TEAM_DARK = ['#1e3a8a', '#7f1d1d'];
const TEAM_LIGHT = ['#93c5fd', '#fca5a5'];

const T_GRASS = 0;
const T_WATER = 1;
const T_FOREST = 2;

// Unités ---------------------------------------------------------------------
const UNIT_TYPES = {
  worker: {
    name: 'Paysan', hp: 60, speed: 75, dmg: 4, range: 6, cooldown: 1.2, sight: 200,
    cost: 50, time: 8, pop: 1, radius: 9, armor: 0, letter: 'Pa',
    desc: "Récolte l'or et bâtit les édifices du royaume.",
  },
  spearman: {
    name: 'Piquier', hp: 130, speed: 65, dmg: 11, range: 8, cooldown: 1.0, sight: 220,
    cost: 60, time: 10, pop: 1, radius: 10, armor: 2, letter: 'Pi',
    bonus: { knight: 2.2 },
    desc: 'Fantassin armé d\'une longue pique. Redoutable contre la cavalerie.',
  },
  archer: {
    name: 'Archer', hp: 75, speed: 70, dmg: 10, range: 175, cooldown: 1.4, sight: 260,
    cost: 70, time: 11, pop: 1, radius: 9, armor: 0, letter: 'Ar', projectile: 'arrow',
    bonus: { spearman: 1.6 },
    desc: 'Tire des volées de flèches. Efficace contre les piquiers.',
  },
  knight: {
    name: 'Chevalier', hp: 210, speed: 115, dmg: 17, range: 8, cooldown: 1.2, sight: 240,
    cost: 140, time: 15, pop: 2, radius: 12, armor: 3, letter: 'Ch',
    bonus: { archer: 1.8, catapult: 2.2, worker: 1.5 },
    desc: 'Cavalerie lourde en armure. Écrase archers et engins de siège.',
  },
  catapult: {
    name: 'Trébuchet', hp: 120, speed: 40, dmg: 40, range: 290, cooldown: 3.8, sight: 260,
    cost: 200, time: 20, pop: 3, radius: 13, armor: 1, letter: 'Tr', projectile: 'stone',
    splash: 42, buildingBonus: 3, minRange: 70,
    desc: 'Engin de siège : projette des pierres qui dévastent murailles et châteaux. Portée minimale.',
  },
};

// Bâtiments ------------------------------------------------------------------
const BUILDING_TYPES = {
  hq: {
    name: 'Château', w: 3, h: 3, hp: 1600, sight: 300, cost: 400, time: 60,
    pop: 10, armor: 3, trains: ['worker'], dropoff: true,
    desc: "Cœur du royaume. Forme les paysans et reçoit l'or. +10 population.",
  },
  house: {
    name: 'Chaumière', w: 2, h: 2, hp: 450, sight: 160, cost: 100, time: 15, pop: 8, armor: 1,
    desc: 'Augmente la population maximale de 8.',
  },
  barracks: {
    name: 'Caserne', w: 3, h: 3, hp: 900, sight: 220, cost: 150, time: 25, armor: 2,
    trains: ['spearman', 'archer'],
    desc: 'Forme les piquiers et les archers.',
  },
  stable: {
    name: 'Écurie', w: 3, h: 3, hp: 900, sight: 220, cost: 200, time: 30, armor: 2,
    trains: ['knight'], requires: 'barracks',
    desc: 'Forme les chevaliers. Nécessite une caserne.',
  },
  workshop: {
    name: 'Atelier de siège', w: 3, h: 3, hp: 900, sight: 220, cost: 250, time: 35, armor: 2,
    trains: ['catapult'], requires: 'barracks',
    desc: 'Construit les trébuchets. Nécessite une caserne.',
  },
  tower: {
    name: 'Tour d\'archers', w: 2, h: 2, hp: 700, sight: 300, cost: 125, time: 25, armor: 3,
    dmg: 14, range: 230, cooldown: 1.5, projectile: 'arrow',
    desc: 'Tour fortifiée qui tire sur les ennemis à portée.',
  },
  wall: {
    name: 'Muraille', w: 1, h: 1, hp: 350, sight: 64, cost: 15, time: 4, armor: 5,
    desc: 'Section de rempart en pierre qui bloque le passage. Maj + clic pour en poser plusieurs.',
  },
};

const BUILD_ORDER_KEYS = [
  ['house', 'Q'], ['barracks', 'W'], ['stable', 'E'], ['workshop', 'R'], ['tower', 'T'], ['wall', 'Y'], ['hq', 'U'],
];
const TRAIN_KEYS = ['Q', 'W', 'E', 'R'];

const MINE_W = 2;
const MINE_H = 2;
const GATHER_AMOUNT = 10;
const GATHER_TIME = 2.0;

const DIFFICULTIES = {
  facile: { label: 'Facile', gatherMult: 0.75, firstWave: 330, waveBase: 5, waveGrow: 2, maxWorkers: 10, startGold: 300, trainChance: 0.3, maxArmyPop: 25 },
  normal: { label: 'Normal', gatherMult: 1.0, firstWave: 240, waveBase: 8, waveGrow: 3, maxWorkers: 14, startGold: 400, trainChance: 0.5, maxArmyPop: 45 },
  difficile: { label: 'Difficile', gatherMult: 1.3, firstWave: 170, waveBase: 10, waveGrow: 4, maxWorkers: 18, startGold: 600, trainChance: 1, maxArmyPop: 150 },
};

// Avatars (héros) --------------------------------------------------------------
const HEROES = {
  roi: {
    name: 'Arthus', title: 'Le Roi', look: 'king',
    hp: 650, dmg: 24, armor: 4, speed: 95, range: 8, aura: 0.25,
    desc: 'Souverain inspirant : son aura donne +25 % de dégâts aux troupes proches.',
  },
  reine: {
    name: 'Aliénor', title: 'La Reine', look: 'queen',
    hp: 480, dmg: 19, armor: 2, speed: 105, range: 190, projectile: 'arrow', aura: 0.15,
    desc: 'Archère royale : tire à cheval depuis une longue distance. Aura +15 %.',
  },
  chevalier: {
    name: 'Gauvain', title: 'Le Chevalier Noir', look: 'blackknight',
    hp: 900, dmg: 32, armor: 6, speed: 88, range: 8, aura: 0.15,
    desc: 'Champion invincible au corps à corps, très résistant. Aura +15 %.',
  },
};
const ENEMY_HERO = {
  name: 'Mordred', title: 'Le Seigneur Rouge', look: 'redlord',
  hp: 650, dmg: 26, armor: 4, speed: 90, range: 8, aura: 0.2,
  desc: 'Tyran cruel qui mène lui-même ses armées.',
};
const HERO_BASE = { sight: 320, cooldown: 1.0, cost: 0, time: 0, pop: 0, radius: 17, letter: '♛' };
const HERO_RESPAWN = 45;
const HERO_MAX_LEVEL = 10;
const AURA_RADIUS = 200;
const WARCRY = { cooldown: 40, duration: 8, radius: 260, dmg: 0.3, speed: 0.35 };
