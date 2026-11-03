# Envol — guide de leveling en français pour WoW Forever

Dépôt **privé** et personnel. Chaque jour, GitHub reconstruit l'addon à partir des routes publiques
à jour de [RestedXP](https://github.com/RestedXP/RXPGuides) (CC BY-NC-SA 4.0) et de
[Polestar](https://github.com/fitzforge/polestar) (GPLv3), lance les tests, puis publie une nouvelle
version (onglet *Releases*) seulement s'il y a du changement.

## Sur le PC
1. Téléchargez `Envol-MiseAJour.zip` dans la dernière *Release*, dézippez-le où vous voulez.
2. Double-cliquez sur **Mettre a jour Envol.bat** (la première fois : dossier AddOns + jeton GitHub en lecture seule).
3. Facultatif : **Activer la mise a jour automatique.bat** (vérification à chaque ouverture de session Windows).

En jeu : `/envol version` affiche la version installée et la date des routes.

## Construire à la main
```
pip install lupa
python tools/build.py      # clone les sources, construit, teste, écrit dist/Envol.zip
```

## Licences
Usage personnel uniquement : les routes RestedXP (CC BY-NC-SA) et Polestar (GPLv3) ne peuvent pas être
redistribuées ensemble. Ne rendez pas ce dépôt public. Détails : `addon/Envol/LICENCES.txt`.
