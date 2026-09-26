# Guerre des Royaumes

Jeu de stratégie médiéval en temps réel, jouable dans le navigateur. An de grâce 1214 : le Seigneur Rouge menace vos terres.
Rassemblez vos paysans, fortifiez votre domaine, levez une armée de piquiers, d'archers, de chevaliers et de trébuchets,
puis commandez-la pour abattre le château ennemi.

Aucune dépendance ni compilation : HTML5 Canvas et JavaScript pur.

## Lancer le jeu

Ouvrez `index.html` dans un navigateur récent (Chrome, Firefox, Edge…).

Vous pouvez aussi utiliser un petit serveur local :

```bash
python3 -m http.server 8000
# puis ouvrir http://localhost:8000
```

## Objectif

Raser **le château et tous les bâtiments** du Seigneur Rouge (en rouge) avant qu'il ne détruise les vôtres (en bleu). Les murailles ne comptent pas.

## Contrôles

| Action | Commande |
| --- | --- |
| Sélectionner | Clic gauche, ou glisser pour une sélection en rectangle |
| Ajouter/retirer de la sélection | `Maj` + clic |
| Sélectionner toutes les unités du même type à l'écran | Double-clic |
| Ordre contextuel (déplacer, attaquer, récolter, construire, ralliement) | Clic droit |
| Attaque-mouvement | `A` puis clic (sur la carte ou la mini-carte) |
| Stop / Tenir la position | `S` / `H` |
| Menu de construction (paysans) | `B` puis `Q` `W` `E` `R` `T` `Y` `U` |
| Poser plusieurs bâtiments (ex. une ligne de murailles) | `Maj` + clic |
| Former des unités (bâtiment sélectionné) | `Q` `W` … |
| Groupes de contrôle | `Ctrl` + `1`–`9` pour créer, `1`–`9` pour rappeler (deux fois = centrer) |
| Caméra | Flèches, bord de l'écran, clic molette, mini-carte ; molette = zoom |
| Centrer la caméra | `Espace` |
| Paysan inactif suivant | `.` |
| Pause | `P` |
| Annuler | `Échap` ou clic droit |

## Unités

| Unité | Coût | Bâtiment | Rôle |
| --- | --- | --- | --- |
| Paysan | 50 | Château | Récolte l'or, bâtit les édifices |
| Piquier | 60 | Caserne | Infanterie robuste, **brise les charges de cavalerie** |
| Archer | 70 | Caserne | Tir à distance, **décime les piquiers** |
| Chevalier | 140 | Écurie | Cavalerie lourde, **écrase archers et trébuchets** |
| Trébuchet | 200 | Atelier de siège | Dégâts de zone, **abat murailles et châteaux**, portée minimale |

## Bâtiments

| Bâtiment | Coût | Rôle |
| --- | --- | --- |
| Château | 400 | Forme les paysans, reçoit l'or, +10 population |
| Chaumière | 100 | +8 population |
| Caserne | 150 | Piquiers et archers |
| Écurie | 200 | Chevaliers (nécessite une caserne) |
| Atelier de siège | 250 | Trébuchets (nécessite une caserne) |
| Tour d'archers | 125 | Défense automatique à distance |
| Muraille | 15 | Rempart qui bloque le passage (se raccorde aux sections voisines) |

## Fonctionnalités

- Carte générée aléatoirement et symétrique (lacs, forêts, mines d'or)
- Brouillard de guerre et zones explorées
- Recherche de chemin A* et déplacement en formation
- Système de contres (pierre-feuille-ciseaux) et armure
- IA adverse qui gère son économie, construit sa base, s'adapte à votre armée et attaque par vagues
- Trois niveaux de difficulté, vitesse de jeu réglable, statistiques de fin de partie

## Structure du code

```
index.html        Page et interface
css/style.css     Styles de l'interface
js/config.js      Statistiques des unités, bâtiments et difficultés
js/world.js       Génération de la carte et recherche de chemin (A*)
js/game.js        État du jeu, ordres, combat, récolte, construction, brouillard
js/ai.js          Intelligence artificielle ennemie
js/render.js      Rendu Canvas et mini-carte
js/ui.js          Contrôles, panneaux d'interface et boucle principale
```
