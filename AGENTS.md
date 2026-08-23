# Instructions de projet — Capote

## Produit

Capote est un utilitaire personnel macOS en Swift/SwiftUI. Il empêche la veille
à la fermeture du capot au moyen de `pmset -a disablesleep`, puis restaure le
comportement normal à la fin de la session.

## Environnement de référence

- macOS 14 ou ultérieur ;
- Swift Package Manager et outils de développement Apple ;
- application de barre des menus et compagnon iOS local, sans relais Internet ;
- clés de jumelage propres à chaque appareil, conservées uniquement dans le
  Trousseau local ;
- installation personnelle manuelle dans `/Applications`.

## Commandes de validation

Exécuter avant toute proposition d’intégration :

```sh
./scripts/test.sh
./scripts/build-app.sh
```

Les artefacts générés se trouvent dans `dist/` et ne sont pas versionnés.

## Sécurité opérationnelle

- Ne jamais exécuter une mutation réelle de `pmset` dans un test automatisé.
- Les tests du helper privilégié doivent utiliser son mode d’essai à blanc.
- Vérifier que `pmset -g live` conserve son état `SleepDisabled` après les tests.
- Ne pas installer, remplacer, lancer ou activer `/Applications/Capote.app` sans
  demande explicite de l’utilisateur.
- Ne jamais contourner l’avertissement thermique : un Mac actif et fermé doit
  rester correctement ventilé.
- Ne pas ajouter de mécanisme de conservation du mot de passe administrateur.
- Ne jamais ouvrir le contrôle réseau par défaut ni accepter une commande non
  chiffrée, expirée, rejouée ou provenant d’un appareil révoqué.
- Ne pas enregistrer le daemon privilégié avec une signature ad hoc : son client
  XPC doit être authentifié par bundle identifier et Team ID stables.

## Organisation du code

- `Sources/Capote/` : interface de barre des menus et contrôleur de session ;
- `Sources/CapoteSessionHelper/` : helper de restauration privilégié ;
- `Tests/CapoteTests/` : tests Swift ;
- `scripts/` : tests et construction du bundle ;
- `packaging/` : métadonnées de l’application.

## Git et livraisons

Le projet suit Git Flow :

- `main` : versions personnelles stables et installables ;
- `staging` : validation préalable à la livraison ;
- `develop` : intégration ;
- `feature/*`, `release/*`, `hotfix/*` : travail isolé.

Ne pas committer directement sur `main`, `staging` ou `develop`. Utiliser des
commits Conventional Commits. Une livraison sur `main` doit avoir une version
SemVer cohérente, une branche `release/X.Y.Z` conservée et un tag annoté
`vX.Y.Z`. Aucun dépôt distant, push ou publication ne doit être créé sans
autorisation explicite.
