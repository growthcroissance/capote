# Capote pour iPhone — prototype personnel

Le compagnon découvre et jumelle d’abord Capote avec Bonjour sur le même réseau
local. Le jumelage utilise un code aléatoire de 96 bits affiché une seule fois
par le Mac. Une clé distincte est ensuite conservée dans le Trousseau de chaque
appareil ; les commandes et réponses sont chiffrées avec ChaCha20-Poly1305.

Une fois jumelé, le compagnon peut aussi joindre le Mac à travers le réseau
privé Tailscale de l’utilisateur. Ce chemin est un transport supplémentaire : il
ne remplace ni les clés Capote, ni l’expiration de 30 secondes, ni la protection
contre le rejeu.

Capote macOS et le compagnon iOS sont deux applications distinctes conservées
dans le même dépôt. Le target iOS dépend du produit Swift Package local
`CapoteRemoteCore`, qui porte leur protocole, leur chiffrement et la validation
stricte des destinations Tailscale.

## Prérequis

- Xcode complet avec le SDK iOS 17 ou ultérieur ;
- un iPhone réel pour valider l’autorisation de réseau local ;
- une équipe de signature sélectionnée dans Xcode pour le target
  `CapoteCompanion` ;
- pour l’accès distant, Tailscale connecté au même tailnet sur le Mac et
  l’iPhone.

Ouvrir `CapoteCompanion.xcodeproj`, choisir l’iPhone et exécuter le scheme
`CapoteCompanion`. Une Personal Team suffit pour un essai personnel, avec les
limites de reprovisionnement imposées par Apple.

## Configuration Tailscale

1. Installer Tailscale sur le Mac et l’iPhone et connecter les deux appareils au
   même tailnet personnel.
2. Sur le réseau local, activer « Autoriser le contrôle depuis un iPhone » dans
   Capote macOS et effectuer le jumelage Bonjour normal.
3. Dans Tailscale, relever soit le nom MagicDNS complet du Mac, terminé par
   `.ts.net`, soit son adresse IP Tailscale.
4. Dans le compagnon, sélectionner le Mac, ouvrir « Configurer l’accès
   Tailscale… » et enregistrer cette destination.
5. Ouvrir le compagnon et actualiser l’état. Capote essaie immédiatement le
   réseau local, puis démarre Tailscale 250 ms plus tard si nécessaire ; le
   premier transport qui répond correctement est conservé. Le Wi-Fi local reste
   donc prioritaire lorsque le VPN est coupé, tandis que Tailscale prend le
   relais si Bonjour est indisponible ou obsolète.

Pour supprimer un ancien jumelage sur l’iPhone, sélectionner le Mac puis toucher
« Oublier ce Mac… ». Le balayage de sa ligne vers la gauche reste disponible
comme raccourci. Révoquer l’iPhone sur le Mac ne supprime pas automatiquement la
clé déjà conservée sur l’iPhone : les deux côtés doivent être oubliés avant un
nouveau jumelage.

Capote écoute le port TCP privé `51684`. Il ne faut activer ni Tailscale Funnel,
ni Tailscale Serve, ni redirection de port sur la box. Le compagnon refuse une
adresse publique arbitraire, une adresse LAN classique et un nom qui ne se
termine pas par `.ts.net`.

## Périmètre sans adhésion Apple payante

Le prototype sait lire l’état du Mac et demander l’arrêt d’une session Capote
déjà active. Il ne contient aucun daemon root et ne permet pas de démarrer une
session depuis l’iPhone. L’activation initiale et son autorisation administrateur
restent donc effectuées sur le Mac ; l’iPhone sert ensuite au suivi et à l’arrêt.

Le Mac doit rester éveillé, en ligne et Capote doit rester ouverte avec le
contrôle iPhone activé. Aucun protocole de cette branche ne réveille un Mac déjà
endormi.

## Trajectoire CloudKit

Le compagnon envoie ses trames via le protocole interne `CompanionTransport`.
Le transport TCP utilisé pour Bonjour et Tailscale peut ainsi être complété ou
remplacé par un transport CloudKit sans modifier le format des commandes, les
clés propres aux appareils ou les contrôles cryptographiques.

CloudKit n’est pas activé dans cette branche : aucun conteneur iCloud, entitlement
ou schéma distant n’est créé. Cette étape restera soumise à une adhésion Apple
Developer active et à une décision séparée sur la livraison du compagnon.
