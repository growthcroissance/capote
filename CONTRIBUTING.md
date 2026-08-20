# Contribuer à Capote

## Cycle de développement

1. Partir de `develop` et créer une branche `feature/<sujet>`.
2. Garder les changements ciblés et documenter tout comportement visible.
3. Exécuter `./scripts/test.sh` puis `./scripts/build-app.sh`.
4. Intégrer la fonctionnalité dans `develop`, puis valider la version sur une
   branche `release/X.Y.Z` et dans `staging`.
5. Une fois la validation terminée, intégrer la release dans `main`, créer le
   tag annoté `vX.Y.Z`, puis réaligner `develop`.

Les corrections urgentes partent de `main` sur `hotfix/X.Y.Z` et sont ensuite
reportées vers `staging` et `develop`.

## Commits

Utiliser Conventional Commits, par exemple :

```text
feat: ajouter une condition de fin de session
fix: restaurer la veille après une erreur du helper
docs: préciser le test manuel du capot
```

## Validation manuelle

Les tests automatisés ne doivent jamais changer réellement `SleepDisabled`.
Les essais qui demandent une autorisation administrateur, ferment le capot ou
remplacent l’application installée sont manuels et nécessitent une demande
explicite.
