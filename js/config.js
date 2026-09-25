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
    name: 'Ouvrier', hp: 60, speed: 75, dmg: 4, range: 6, cooldown: 1.2, sight: 200,
    cost: 50, time: 8, pop: 1, radius: 9, armor: 0, letter: 'O',
    desc: "Récolte l'or et construit les bâtiments.",
  },
  spearman: {
    name: 'Lancier', hp: 130, speed: 65, dmg: 11, range: 8, cooldown: 1.0, sight: 220,
    cost: 60, time: 10, pop: 1, radius: 10, armor: 2, letter: 'L',
    bonus: { knight: 2.2 },
    desc: 'Infanterie robuste. Très efficace contre la cavalerie.',
  },
  archer: {
    name: 'Archer', hp: 75, speed: 70, dmg: 10, range: 175, cooldown: 1.4, sight: 260,
    cost: 70, time: 11, pop: 1, radius: 9, armor: 0, letter: 'A', projectile: 'arrow',
    bonus: { spearman: 1.6 },
    desc: 'Attaque à distance. Efficace contre les lanciers.',
  },
  knight: {
    name: 'Chevalier', hp: 210, speed: 115, dmg: 17, range: 8, cooldown: 1.2, sight: 240,
    cost: 140, time: 15, pop: 2, radius: 12, armor: 3, letter: 'C',
    bonus: { archer: 1.8, catapult: 2.2, worker: 1.5 },
    desc: 'Cavalerie rapide. Écrase archers et engins de siège.',
  },
  catapult: {
    name: 'Catapulte', hp: 120, speed: 40, dmg: 40, range: 290, cooldown: 3.8, sight: 260,
    cost: 200, time: 20, pop: 3, radius: 13, armor: 1, letter: 'K', projectile: 'stone',
    splash: 42, buildingBonus: 3, minRange: 70,
    desc: 'Engin de siège : dégâts de zone, dévaste les bâtiments. Portée minimale.',
  },
};

// Bâtiments ------------------------------------------------------------------
const BUILDING_TYPES = {
  hq: {
    name: 'Quartier Général', w: 3, h: 3, hp: 1600, sight: 300, cost: 400, time: 60,
    pop: 10, armor: 3, trains: ['worker'], dropoff: true,
    desc: "Centre de la base. Forme les ouvriers et reçoit l'or. +10 population.",
  },
  house: {
    name: 'Maison', w: 2, h: 2, hp: 450, sight: 160, cost: 100, time: 15, pop: 8, armor: 1,
    desc: 'Augmente la population maximale de 8.',
  },
  barracks: {
    name: 'Caserne', w: 3, h: 3, hp: 900, sight: 220, cost: 150, time: 25, armor: 2,
    trains: ['spearman', 'archer'],
    desc: 'Forme les lanciers et les archers.',
  },
  stable: {
    name: 'Écurie', w: 3, h: 3, hp: 900, sight: 220, cost: 200, time: 30, armor: 2,
    trains: ['knight'], requires: 'barracks',
    desc: 'Forme les chevaliers. Nécessite une caserne.',
  },
  workshop: {
    name: 'Atelier de siège', w: 3, h: 3, hp: 900, sight: 220, cost: 250, time: 35, armor: 2,
    trains: ['catapult'], requires: 'barracks',
    desc: 'Construit les catapultes. Nécessite une caserne.',
  },
  tower: {
    name: 'Tour de garde', w: 2, h: 2, hp: 700, sight: 300, cost: 125, time: 25, armor: 3,
    dmg: 14, range: 230, cooldown: 1.5, projectile: 'arrow',
    desc: 'Défense statique qui tire sur les ennemis à portée.',
  },
};

const BUILD_ORDER_KEYS = [
  ['house', 'Q'], ['barracks', 'W'], ['stable', 'E'], ['workshop', 'R'], ['tower', 'T'], ['hq', 'Y'],
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
