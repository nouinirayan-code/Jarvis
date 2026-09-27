# 🏝️ L'Île des Reliques — jeu d'aventure Roblox

Un jeu d'aventure complet pour Roblox : explore une île, affronte des monstres, trouve les trois
reliques perdues et terrasse le **Gardien de Pierre** dans le Temple Oublié.

**Tout le monde est généré par le code** : pas besoin de construire quoi que ce soit dans Studio.
Il suffit de coller deux scripts et d'appuyer sur « Jouer ».

## L'aventure

| Lieu | Où ? | Défi |
| --- | --- | --- |
| 🏘️ Village de Brisevent | Centre | Le **Vieux Sage** donne la quête, **Barnabé** tient la boutique |
| 🌲 Forêt Murmurante | Nord | Slimes, escalier en spirale jusqu'au sommet de l'**Arbre Ancien** |
| 💎 Canyon de Cristal | Est | Squelettes, gouffre à franchir sur des **cristaux instables** qui disparaissent |
| 🌋 Mont Braise | Ouest | Diablotins de feu, **anneau de lave** à traverser sur des pierres, coulées de lave |
| 🏛️ Temple Oublié | Sud | La porte ne s'ouvre qu'avec les **3 reliques** → combat contre le **Gardien de Pierre** |

- **Combat à l'épée** (clic), nombres de dégâts flottants, monstres qui lâchent des pièces.
- **Boss** : quand un cercle rouge apparaît au sol, écarte-toi ! À mi-vie, il enrage et invoque des slimes.
  Ses points de vie augmentent avec le nombre de joueurs dans l'arène (jouable à plusieurs).
- **Boutique** : Épée d'acier, Lame de cristal, Bottes du vent, Cœur de héros, Potion de soin.
- **Points de contrôle** dans chaque zone, **titres de zone** à l'écran, quête affichée en permanence.
- **Sauvegarde** automatique des pièces, reliques, équipement et victoires.

## Installation dans Roblox Studio (5 minutes)

1. Ouvre **Roblox Studio** et crée un nouveau jeu avec le modèle **Baseplate**
   (la plaque grise sera retirée automatiquement).
2. Dans l'**Explorer** (menu *Affichage* → *Explorer* si tu ne le vois pas) :
   - fais un clic droit sur **ServerScriptService** → *Insérer un objet* → **Script** ;
   - renomme-le `IleDesReliques` ;
   - ouvre-le, efface tout, puis colle le contenu de
     [`src/server/IleDesReliques.server.luau`](src/server/IleDesReliques.server.luau).
3. Toujours dans l'Explorer, ouvre **StarterPlayer** :
   - clic droit sur **StarterPlayerScripts** → *Insérer un objet* → **LocalScript** ;
   - renomme-le `IleDesReliquesClient` ;
   - colle le contenu de
     [`src/client/IleDesReliquesClient.client.luau`](src/client/IleDesReliquesClient.client.luau).
4. Appuie sur **Jouer** (F5). L'île se construit en quelques secondes. Va parler au Vieux Sage près du puits !

> ⚠️ Le script **remplace le terrain** existant : utilise un jeu vide.

### Activer la sauvegarde

La sauvegarde utilise les DataStores de Roblox. Pour qu'elle fonctionne :

1. Publie ton jeu (*Fichier* → *Publier sur Roblox*).
2. Dans *Accueil* → *Paramètres du jeu* → *Sécurité*, active
   **« Enable Studio Access to API Services »** (pour tester la sauvegarde dans Studio).

Sans ça, le jeu fonctionne normalement, mais la progression n'est pas conservée entre les parties.

### Avec Rojo (optionnel)

Si tu utilises [Rojo](https://rojo.space), le fichier `default.project.json` place automatiquement les scripts :

```bash
rojo serve
```

## Commandes

| Action | PC | Mobile |
| --- | --- | --- |
| Se déplacer | `Z Q S D` / `W A S D` | Joystick |
| Sauter | `Espace` | Bouton saut |
| Frapper | Clic gauche (l'épée doit être équipée : touche `1`) | Toucher l'écran |
| Parler / prendre une relique / commercer | `E` près du personnage ou de l'objet | Bouton d'action |
| Faire défiler un dialogue | Bouton « Continuer » ou `Entrée` | Bouton « Continuer » |

## Personnaliser le jeu

Tout se règle en haut du script serveur, dans la section **RÉGLAGES** :

- `SWORD_DAMAGE` : dégâts des trois épées ;
- `SHOP_ITEMS` : prix et descriptions de la boutique ;
- `ENEMY_TYPES` : points de vie, dégâts, vitesse, pièces lâchées de chaque monstre ;
- `VILLAGE`, `FOREST`, `CANYON`, `VOLCANO`, `TEMPLE`, `ARENA` : position des zones sur l'île.

## Comment c'est fait

- **Script serveur** (`IleDesReliques`) : construit le terrain (océan, plages, collines, chemins, volcan,
  canyon), les bâtiments, les PNJ, les monstres et le boss. Il gère aussi les quêtes, le combat, la boutique,
  les points de contrôle et la sauvegarde.
- **Script client** (`IleDesReliquesClient`) : toute l'interface (pièces, reliques, quête, dialogues,
  boutique, barre du boss, titres de zone, dégâts flottants, écran de victoire).
- Les deux communiquent par des `RemoteEvent` créés dans `ReplicatedStorage/IleRemotes`.
