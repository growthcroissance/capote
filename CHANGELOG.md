# Journal des modifications

Ce projet suit [Semantic Versioning](https://semver.org/lang/fr/).

## [Non publié]

### Ajouté

- image disque DMG vérifiée avec fenêtre Finder aux couleurs de GROWTH
  Croissance, installation par glisser-déposer vers Applications, somme SHA-256
  et attestation de provenance GitHub ;
- construction reproductible du DMG avec une révision épinglée de `dmgbuild`,
  sans automatisation Finder, compatible avec le fond d’image sous macOS 26.

## [1.2.0] - 2026-08-21

### Ajouté

- option de barre des menus pour activer ou désactiver le lancement automatique
  de Capote à l’ouverture de session, avec lecture de l’état réel de macOS et
  accès aux Réglages Système lorsqu’une approbation est requise.

## [1.1.0] - 2026-08-21

### Ajouté

- vérification automatique et manuelle des nouvelles GitHub Releases stables ;
- proposition de téléchargement guidé vers la page officielle, sans mise à jour
  intégrée incompatible avec la signature ad hoc actuelle.

## [1.0.1] - 2026-08-21

### Corrigé

- restauration privilégiée de secours lorsqu’un helper de session ne répond
  plus à la demande d’annulation ;
- exclusion globale empêchant deux helpers Capote de modifier simultanément
  `SleepDisabled`.

## [1.0.0] - 2026-08-21

Première version publique de Capote.

### Ajouté

- licence propriétaire autorisant l’audit et la compilation locale de
  vérification sans autoriser la redistribution ;
- politique de signalement privé des vulnérabilités ;
- page GitHub de téléchargement et workflows de validation, de publication et
  d’attestation de provenance.
- branding GROWTH Croissance dans l’application et ses métadonnées ;
- liens vers le site GROWTH Croissance et vers un soutien PayPal facultatif ;
- archive de partage universelle Apple Silicon/Intel avec guide d’installation
  et somme de contrôle SHA-256 ;
- documentation des limites de la signature ad hoc et du futur parcours de
  notarisation Apple.

## [0.5.0] - 2026-08-21

### Ajouté

- restauration automatique de la veille lorsque macOS signale un état
  thermique sérieux ou critique ;
- notification locale indiquant le motif de l’arrêt de sécurité ;
- simulation thermique en mode d’essai à blanc du helper privilégié.

## [0.4.0] - 2026-08-20

Première version suivie dans Git à partir de l’utilitaire personnel existant.

### Ajouté

- activation et restauration de `SleepDisabled` depuis la barre des menus ;
- sessions limitées par durée ou par date et heure ;
- sessions liées à l’exécution d’une application ;
- sessions liées à la progression d’un téléchargement ;
- helper privilégié de restauration avec entrées strictement validées ;
- scripts de test, de construction, de signature ad hoc et d’archivage.
