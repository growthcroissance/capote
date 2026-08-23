# Partager Capote

## Canal officiel

Le dépôt GitHub public rend le code consultable pour audit, sous une licence
propriétaire qui interdit sa redistribution et son exploitation commerciale.
Les seuls binaires officiels sont ceux joints aux
[GitHub Releases](https://github.com/growthcroissance/capote/releases).

Chaque tag `vX.Y.Z` déclenche une construction propre sur GitHub Actions, la
publication du DMG, du ZIP et de leurs sommes SHA-256, ainsi qu’une attestation
de provenance pour les deux artefacts. Celle du DMG se vérifie avec :

```sh
gh attestation verify Capote-X.Y.Z.dmg -R growthcroissance/capote
```

La page GitHub Pages située dans `docs/` présente le téléchargement, les limites
de la distribution et les liens d’audit sans traceur ni dépendance externe.

## Artefacts à transmettre

Les commandes suivantes produisent un ZIP et une image disque universels pour
les Mac Apple Silicon et Intel, avec leurs sommes de contrôle SHA-256 :

```sh
./scripts/build-app.sh
./scripts/prepare-packaging-tools.sh
./scripts/build-dmg.sh
```

Le script de préparation installe dans `.build/dmg-venv` la version publiée
`dmgbuild 1.6.5`, épinglée par empreinte SHA-256 avec ses dépendances. Il lui
applique le correctif minimal repris de la révision officielle
`42ff59afb50907c6305cdbc658d34e6fe3a81828` pour le fond d’image sous macOS 26.
Les métadonnées Finder sont ainsi construites directement, sans piloter Finder
par AppleScript.

Joindre ensemble les quatre fichiers générés dans `dist/` à la GitHub Release :

- `Capote-X.Y.Z.dmg` ;
- `Capote-X.Y.Z.dmg.sha256` ;
- `Capote-X.Y.Z.zip` ;
- `Capote-X.Y.Z.zip.sha256`.

Le DMG contient un dossier Documentation réunissant `LICENSE.md` et le guide
d’installation ; le ZIP les contient à sa racine. Les droits d’usage et d’audit
accompagnent ainsi toujours le binaire. Le DMG est le parcours d’installation
recommandé ; le ZIP reste utile pour remplacer une installation existante ou
comme solution de repli.

Publier également la somme SHA-256 dans le texte de l’annonce ou de la release,
afin qu’elle ne soit pas uniquement fournie à côté de l’archive qu’elle doit
authentifier.

## Limite de cette première distribution

Le bundle est signé localement de façon ad hoc. Il n’est pas signé avec un
certificat Apple Developer ID et n’est pas notarié. Au premier lancement, un
destinataire doit donc faire un clic droit sur l’application, choisir
« Ouvrir », puis confirmer l’ouverture.

Capote est un projet personnel gratuit encore diffusé à petite échelle. Le coût
récurrent du programme Apple Developer n’a donc pas été engagé à ce stade.
Puisque l’application agit sur un réglage système et demande une autorisation
administrateur, le code correspondant aux versions distribuées reste
entièrement consultable pour audit. Ne pas présenter cette transparence comme un
substitut à la signature Developer ID ou à la notarisation Apple.

Ne pas présenter ces artefacts comme « signés et notariés ». Pour supprimer cet
avertissement, il faudra :

1. disposer d’un compte Apple Developer et d’un certificat Developer ID
   Application ;
2. signer l’application et son helper avec ce certificat et le runtime renforcé ;
3. envoyer l’archive au service de notarisation Apple ;
4. agrafer le ticket de notarisation au bundle ;
5. reconstruire et vérifier l’archive finale avec `spctl` et `codesign`.

## Vérification des mises à jour dans l’application

Capote interroge l’API publique `releases/latest` du dépôt officiel au lancement
et à la demande depuis son menu. Seules une version stable au format `vX.Y.Z` et
une page HTTPS appartenant exactement au dépôt `growthcroissance/capote` sont
acceptées. Une proposition automatique déjà présentée n’est pas répétée pour la
même version ; la vérification manuelle reste toujours disponible.

Le mécanisme ouvre la page de la GitHub Release après confirmation. Il ne
télécharge pas, ne décompresse pas, ne remplace pas et ne relance pas
l’application. Un updater intégré ne doit être envisagé qu’après la mise en
place d’une signature Developer ID stable, de la notarisation et d’un mécanisme
de validation cryptographique des mises à jour. Jusque-là, l’utilisateur garde
la possibilité de vérifier la somme SHA-256 et l’attestation avant de remplacer
manuellement `Capote.app`.

## Checklist avant partage

- exécuter `./scripts/test.sh`, `./scripts/build-app.sh`,
  `./scripts/prepare-packaging-tools.sh` puis `./scripts/build-dmg.sh` ;
- vérifier que `pmset -g live` indique toujours `SleepDisabled 0` ;
- vérifier les deux architectures avec `lipo -info` ;
- monter le DMG, vérifier le fond, le positionnement des icônes, le raccourci
  Applications et le glisser-déposer ;
- tester le ZIP extrait sur un autre compte macOS ou un autre Mac ;
- rappeler clairement l’avertissement thermique ;
- publier le DMG, le ZIP, leurs sommes SHA-256 et les notes de version ;
- vérifier que les attestations GitHub correspondent aux artefacts publiés ;
- ne jamais joindre de mot de passe, certificat privé ou profil de signature.

## Soutien facultatif

Le lien intégré utilise la page de don PayPal hébergée créée pour Capote :
`https://www.paypal.com/donate/?hosted_button_id=568Y4MLLJSUXE`. Elle propose
4,95 €, 9,95 € ou 14,95 €, ainsi qu’un montant libre en euros. Les dons peuvent
être ponctuels ou annuels. Si cette page est remplacée dans PayPal,
mettre également à jour l’URL centralisée dans
`CapoteBranding.donationURL`, le README et le guide inclus dans l’archive.

Un compagnon iOS de Capote est en cours de développement. Sa future
distribution nécessitera une adhésion à l’Apple Developer Program. Les dons
facultatifs contribueront notamment à financer cet abonnement annuel.
