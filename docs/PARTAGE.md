# Partager Capote

## Canal officiel

Le dépôt GitHub public rend le code consultable pour audit, sous une licence
propriétaire qui interdit sa redistribution et son exploitation commerciale.
Les seuls binaires officiels sont ceux joints aux
[GitHub Releases](https://github.com/growthcroissance/capote/releases).

Chaque tag `vX.Y.Z` déclenche une construction propre sur GitHub Actions, la
publication de l’archive et de sa somme SHA-256, ainsi qu’une attestation de
provenance. Elle se vérifie avec :

```sh
gh attestation verify Capote-X.Y.Z.zip -R growthcroissance/capote
```

La page GitHub Pages située dans `docs/` présente le téléchargement, les limites
de la distribution et les liens d’audit sans traceur ni dépendance externe.

## Artefacts à transmettre

La commande suivante produit une archive universelle pour les Mac Apple
Silicon et Intel, ainsi que sa somme de contrôle SHA-256 :

```sh
./scripts/build-app.sh
```

Joindre ensemble les deux fichiers générés dans `dist/` à la GitHub Release :

- `Capote-X.Y.Z.zip` ;
- `Capote-X.Y.Z.zip.sha256`.

L’archive contient également `LICENSE.md`, afin que les droits d’usage et
d’audit accompagnent toujours le binaire.

Publier également la somme SHA-256 dans le texte de l’annonce ou de la release,
afin qu’elle ne soit pas uniquement fournie à côté de l’archive qu’elle doit
authentifier.

## Limite de cette première distribution

Le bundle est signé localement de façon ad hoc. Il n’est pas signé avec un
certificat Apple Developer ID et n’est pas notarié. Au premier lancement, un
destinataire doit donc faire un clic droit sur l’application, choisir
« Ouvrir », puis confirmer l’ouverture.

Ne pas présenter cette archive comme « signée et notariée ». Pour supprimer cet
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

- exécuter `./scripts/test.sh` puis `./scripts/build-app.sh` ;
- vérifier que `pmset -g live` indique toujours `SleepDisabled 0` ;
- vérifier les deux architectures avec `lipo -info` ;
- tester l’archive extraite sur un autre compte macOS ou un autre Mac ;
- rappeler clairement l’avertissement thermique ;
- publier l’archive, sa somme SHA-256 et les notes de version ;
- vérifier que l’attestation GitHub correspond à l’archive publiée ;
- ne jamais joindre de mot de passe, certificat privé ou profil de signature.

## Soutien facultatif

Le lien intégré utilise la page de don PayPal hébergée créée pour Capote :
`https://www.paypal.com/donate/?hosted_button_id=568Y4MLLJSUXE`. Elle propose
4,95 €, 9,95 € ou 14,95 €, ainsi qu’un montant libre en euros. Les dons peuvent
être ponctuels ou annuels. Si cette page est remplacée dans PayPal,
mettre également à jour l’URL centralisée dans
`CapoteBranding.donationURL`, le README et le guide inclus dans l’archive.
