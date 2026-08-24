# Capote pour iPhone — prototype local

Le compagnon découvre Capote avec Bonjour sur le même réseau local. Le jumelage
utilise un code aléatoire de 96 bits affiché une seule fois par le Mac. Une clé
distincte est ensuite conservée dans le Trousseau de chaque appareil ; les
commandes et réponses sont chiffrées avec ChaCha20-Poly1305.

Capote macOS et le compagnon iOS sont deux applications distinctes conservées
dans le même dépôt. Le target iOS dépend du produit Swift Package local
`CapoteRemoteCore`, qui porte leur protocole et leur chiffrement communs.

## Prérequis

- Xcode complet avec le SDK iOS 17 ou ultérieur ;
- un iPhone réel pour valider l’autorisation de réseau local ;
- une équipe de signature sélectionnée dans Xcode pour le target
  `CapoteCompanion`.

Ouvrir `CapoteCompanion.xcodeproj`, choisir l’iPhone et exécuter le scheme
`CapoteCompanion`. Une Personal Team suffit pour un essai personnel, avec les
limites de reprovisionnement imposées par Apple.

## Périmètre sans adhésion payante

Le prototype sait lire l’état du Mac et demander l’arrêt d’une session Capote
déjà active. Il ne contient aucun daemon root et ne permet pas de démarrer une
session depuis l’iPhone. L’activation initiale et son autorisation administrateur
restent donc effectuées sur le Mac ; l’iPhone sert ensuite au suivi et à l’arrêt.

Aucun relais Internet, compte Capote, serveur distant ou télémétrie n’est ajouté.
