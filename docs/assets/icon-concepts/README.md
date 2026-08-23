# Direction finale — B1 Équilibre

Cette direction a été validée visuellement par Benjamin. Elle reste isolée des
actifs actuellement consommés par l’application, le site et le packaging.

## Sources finales

- `capote-icon-b1-final.svg` : source vectorielle de l’icône couleur ;
- `capote-icon-b1-final-1024.png` : rendu maître RGBA 1024 × 1024 ;
- `capote-icon-b1-mark-monochrome.svg` : symbole noir sur fond transparent ;
- `capote-icon-b1-mark-monochrome-16.png` et
  `capote-icon-b1-mark-monochrome-32.png` : contrôles de petite taille ;
- `capote-icon-b1-final.iconset/` : dix PNG aux tailles macOS standard.

Palette :

- corail : `#F54D38` ;
- encre : `#171717` ;
- blanc chaud : `#FFFAF7`.

## Validation locale

- SVG bien formés, sans texte intégré, filtre, dégradé ni ombre ;
- rendu couleur et symbole monochrome contrôlés à 16 et 32 px ;
- dix PNG de l’iconset présents avec leurs dimensions attendues de 16 à
  1024 px et un canal alpha.

Le script `scripts/build-icon.py` assemble les dix représentations standard
avec leurs types Retina dédiés. L’ICNS produit a été réextrait avec `iconutil` :
les dix fichiers et leurs dimensions de 16 à 1024 px sont retrouvés exactement.

## Limite de cette phase

Sur la branche `feature/app-icon-redesign`, le site, le bundle et le packaging
consomment désormais B1. Les symboles dynamiques de la barre des menus restent
`eye.fill` et `moon.zzz` afin de préserver l’indication d’état actuelle.
