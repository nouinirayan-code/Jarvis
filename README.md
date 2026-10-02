# 🕯️ Le Manoir des Ombres — escape horreur pour Roblox

Tu es enfermé, la nuit, dans un manoir plongé dans le noir. Quelque chose y rôde : **le Veilleur**.
Résous les énigmes et fuis avant l'aube… sans te faire attraper.

**Tout le manoir est généré par le code** : il suffit de coller deux scripts dans Roblox Studio.

![Plan du manoir](docs/plan-du-manoir.png)

## Comment s'échapper

1. **Trouver les 3 fusibles** cachés dans le manoir.
2. **Rétablir le courant** au boîtier électrique de la **cave** (derrière la cuisine).
   Les lumières se rallument… et la porte du **bureau** se déverrouille. Mais le Veilleur devient plus rapide.
3. **Trouver le code du coffre-fort** : un carnet dans la bibliothèque explique que le code est l'heure à laquelle
   **l'horloge de la salle à manger** s'est arrêtée (le code change à chaque partie !).
4. **Prendre la clé maîtresse** dans le coffre, **ouvrir la porte d'entrée** et courir jusqu'au portail.

## Survivre au Veilleur

- **La lampe torche (F)** éclaire, mais le Veilleur **voit la lumière de très loin**. La batterie s'use : ramasse des piles.
- **Courir (Maj)** est plus rapide mais **fait du bruit** : il t'entend. Ton souffle est limité.
- **Les armoires (E)** te cachent… sauf si le Veilleur t'a **vu y entrer**.
- Un **code faux** au coffre fait du bruit et l'attire.
- Quand il approche, ton cœur bat et l'écran rougit. S'il t'attrape : jumpscare, et tu réapparais dans le hall.
- La manche dure **8 minutes**. Le jeu se joue seul ou **à plusieurs, en coopération** : les fusibles et la clé
  sont partagés par toute l'équipe.

## Installation dans Roblox Studio (5 minutes)

1. Ouvre **Roblox Studio** et crée un jeu avec le modèle **Baseplate**
   (la plaque grise est retirée automatiquement).
2. Dans l'**Explorer** :
   - clic droit sur **ServerScriptService** → *Insérer un objet* → **Script**, renomme-le `ManoirServeur`,
     efface tout et colle le contenu de [`src/server/ManoirServeur.server.luau`](src/server/ManoirServeur.server.luau) ;
   - ouvre **StarterPlayer**, clic droit sur **StarterPlayerScripts** → *Insérer un objet* → **LocalScript**,
     renomme-le `ManoirClient` et colle le contenu de [`src/client/ManoirClient.client.luau`](src/client/ManoirClient.client.luau).
3. Appuie sur **Jouer** (F5). Le Veilleur se réveille 25 secondes après le début…

> 💡 Pour un rendu plus effrayant : dans l'Explorer, sélectionne **Lighting** et mets la propriété
> **Technology** sur **Future** (les ombres de la lampe torche seront bien plus belles).

Avec [Rojo](https://rojo.space) : `rojo serve` (le fichier `default.project.json` place les scripts).

## Commandes

| Action | PC | Mobile / manette |
| --- | --- | --- |
| Se déplacer | `Z Q S D` / `W A S D` | Joystick |
| Courir | `Maj gauche` (maintenir) | Bouton « Courir » |
| Lampe torche | `F` | Bouton « Lampe » / `Y` |
| Ramasser, lire, se cacher, ouvrir | `E` | Bouton d'action |

## Personnaliser

En haut du script serveur, la section **RÉGLAGES** permet de changer : la durée d'une manche, le délai avant le
réveil du monstre, sa vitesse, ses distances de vue et d'ouïe, la vitesse des joueurs et l'usure de la batterie.
