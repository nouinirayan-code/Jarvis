# L'Art de la Guerre

Jeu de stratégie en temps réel (RTS) jouable dans le navigateur : récoltez de l'or, construisez votre base,
entraînez une armée et commandez-la pour détruire la base ennemie contrôlée par l'ordinateur.

Aucune dépendance ni compilation : HTML5 Canvas et JavaScript pur.

## Lancer le jeu

Ouvrez `index.html` dans un navigateur récent (Chrome, Firefox, Edge…).

Vous pouvez aussi utiliser un petit serveur local :

```bash
python3 -m http.server 8000
# puis ouvrir http://localhost:8000
```

## Objectif

Détruire **tous les bâtiments ennemis** (en rouge) avant que l'ennemi ne détruise les vôtres (en bleu).

## Contrôles

| Action | Commande |
| --- | --- |
| Sélectionner | Clic gauche, ou glisser pour une sélection en rectangle |
| Ajouter/retirer de la sélection | `Maj` + clic |
| Sélectionner toutes les unités du même type à l'écran | Double-clic |
| Ordre contextuel (déplacer, attaquer, récolter, construire, ralliement) | Clic droit |
| Attaque-mouvement | `A` puis clic (sur la carte ou la mini-carte) |
| Stop / Tenir la position | `S` / `H` |
| Menu de construction (ouvriers) | `B` puis `Q` `W` `E` `R` `T` `Y` |
| Former des unités (bâtiment sélectionné) | `Q` `W` … |
| Groupes de contrôle | `Ctrl` + `1`–`9` pour créer, `1`–`9` pour rappeler (deux fois = centrer) |
| Caméra | Flèches, bord de l'écran, clic molette, mini-carte ; molette = zoom |
| Centrer la caméra | `Espace` |
| Ouvrier inactif suivant | `.` |
| Pause | `P` |
| Annuler | `Échap` ou clic droit |

## Unités

| Unité | Coût | Bâtiment | Rôle |
| --- | --- | --- | --- |
| Ouvrier | 50 | Quartier Général | Récolte l'or, construit |
| Lancier | 60 | Caserne | Infanterie robuste, **fort contre la cavalerie** |
| Archer | 70 | Caserne | Attaque à distance, **fort contre les lanciers** |
| Chevalier | 140 | Écurie | Rapide, **fort contre archers et catapultes** |
| Catapulte | 200 | Atelier de siège | Dégâts de zone, **dévaste les bâtiments**, portée minimale |

## Bâtiments

| Bâtiment | Coût | Rôle |
| --- | --- | --- |
| Quartier Général | 400 | Forme les ouvriers, dépôt d'or, +10 population |
| Maison | 100 | +8 population |
| Caserne | 150 | Lanciers et archers |
| Écurie | 200 | Chevaliers (nécessite une caserne) |
| Atelier de siège | 250 | Catapultes (nécessite une caserne) |
| Tour de garde | 125 | Défense automatique à distance |

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
