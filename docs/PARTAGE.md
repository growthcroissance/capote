# Partager Capote

## Artefacts à transmettre

La commande suivante produit une archive universelle pour les Mac Apple
Silicon et Intel, ainsi que sa somme de contrôle SHA-256 :

```sh
./scripts/build-app.sh
```

Partager ensemble les deux fichiers générés dans `dist/` :

- `Capote-X.Y.Z.zip` ;
- `Capote-X.Y.Z.zip.sha256`.

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

## Checklist avant partage

- exécuter `./scripts/test.sh` puis `./scripts/build-app.sh` ;
- vérifier que `pmset -g live` indique toujours `SleepDisabled 0` ;
- vérifier les deux architectures avec `lipo -info` ;
- tester l’archive extraite sur un autre compte macOS ou un autre Mac ;
- rappeler clairement l’avertissement thermique ;
- publier l’archive, sa somme SHA-256 et les notes de version ;
- ne jamais joindre de mot de passe, certificat privé ou profil de signature.

## Soutien facultatif

Le lien intégré utilise l’adresse PayPal confirmée
`paypal@growth-croissance.com`, sans montant imposé et en euros. Pour une
diffusion plus large, créer une page de don dans le compte PayPal Business puis
remplacer l’URL centralisée dans `CapoteBranding.donationURL` par le lien fourni
par PayPal.
