# 🔥 Dernière Lueur

Jeu d'action et de survie en vue de dessus, jouable dans le navigateur.
Le monde a sombré dans les ténèbres : vous veillez sur **le dernier foyer**.

- **Le jour**, explorez, coupez du bois, cassez des pierres, trouvez des cristaux de braise et bâtissez vos défenses.
- **La nuit**, les ombres surgissent des ténèbres pour éteindre le foyer. Combattez-les à l'épée.
- **La lumière est votre arme** : dans la lumière du foyer, des torches et des phares, les ombres sont ralenties
  et subissent +50 % de dégâts. Loin de la lumière, votre lanterne se vide et le froid vous ronge.
- Les ombres vaincues laissent des **braises** : elles nourrissent la flamme et permettent d'acheter des améliorations.
- Vous ne pouvez **bâtir que dans la lumière** : chaque torche agrandit votre territoire.
- Si vous tombez, la flamme vous ranime au prix d'une partie de son combustible.
  **Si la flamme s'éteint ou si le foyer est détruit, la partie est perdue.**
- À l'aube, les ombres restantes brûlent. Toutes les 5 nuits, le **Dévoreur** attaque.

Aucune dépendance ni compilation : HTML5 Canvas et JavaScript pur.

## Lancer le jeu

Ouvrez `index.html` dans un navigateur récent, ou lancez un serveur local :

```bash
python3 -m http.server 8000
# puis ouvrir http://localhost:8000
```

## Commandes

| Action | Touche |
| --- | --- |
| Se déplacer | `Z Q S D` (AZERTY) / `W A S D` (QWERTY) / flèches |
| Frapper / récolter | Clic gauche (maintenir) |
| Esquive | `Espace` ou `Maj` |
| Construire | `1` à `5` (ou `B`), puis clic dans une zone éclairée |
| Nourrir le foyer | `F` (1 braise, sinon 5 bois) |
| Améliorations | `U` près du foyer |
| Réparer / démonter la construction visée | `E` (1 bois) / `X` |
| Annuler | Clic droit ou `Échap` |
| Pause | `P` |

## Constructions

| | Coût | Rôle |
| --- | --- | --- |
| Palissade | 3 bois | Bloque les ombres, qui doivent la détruire |
| Torche | 2 bois, 1 pierre | Lumière : ralentit et affaiblit les ombres, agrandit la zone constructible |
| Pièges à pieux | 3 bois, 2 pierres | Blesse les ombres qui marchent dessus |
| Baliste | 6 bois, 5 pierres | Tire automatiquement |
| Phare | 6 pierres, 2 braises | Grande lumière |

## Ombres

Ombre (de base), Rôdeur (rapide, chasse le héros), Cracheur (attaque à distance), Colosse (détruit les
constructions) et le Dévoreur (boss toutes les 5 nuits).

## Structure du code

```
index.html      Page, interface et écrans
css/style.css   Style de l'interface
js/config.js    Réglages : héros, foyer, constructions, ombres, améliorations
js/world.js     Génération de la carte, collisions, chemins des ombres vers le foyer
js/game.js      Simulation : héros, combat, ombres, constructions, cycle jour/nuit
js/render.js    Rendu et éclairage dynamique
js/ui.js        Commandes, interface et boucle principale
```
