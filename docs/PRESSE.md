# Kit presse — Capote

## Présentation courte

Capote est un petit utilitaire français pour macOS qui empêche temporairement
la mise en veille d’un MacBook lorsque son capot est fermé. L’application vit
dans la barre des menus, fonctionne sans compte ni collecte de données et
restaure automatiquement la veille à la fin de la session.

## Faits essentiels

- application native Swift et SwiftUI pour macOS 14 ou ultérieur ;
- compatible Apple Silicon et Intel ;
- sessions minutées, jusqu’à une date choisie, liées à une application ou à
  l’évolution d’un fichier de téléchargement ;
- restauration automatique par un helper embarqué ;
- arrêt de sécurité lorsque macOS signale un état thermique sérieux ou
  critique ;
- aucune conservation du mot de passe administrateur ;
- gratuit, sans compte, sans publicité et sans collecte de données ;
- code consultable pour audit sous licence propriétaire ;
- distribution officielle uniquement depuis les GitHub Releases du projet.

## Signature et transparence

Capote est actuellement signé localement de façon ad hoc et n’est pas notarié
par Apple. Le premier lancement nécessite donc un clic droit sur l’application,
puis « Ouvrir » et une confirmation de macOS.

Le projet étant personnel, gratuit et encore diffusé à petite échelle,
l’adhésion annuelle au programme Apple Developer n’a pas été souscrite à ce
stade. Comme Capote agit sur un réglage système et sollicite une autorisation
administrateur, son code est entièrement consultable afin de permettre un audit
indépendant. Cet accès au code ne remplace pas la vérification d’identité et le
contrôle automatisé qu’apporteraient une signature Developer ID et la
notarisation Apple.

Un compagnon iOS de Capote est également en cours de développement. Sa future
distribution nécessitera l’adhésion à l’Apple Developer Program. Les dons
facultatifs reçus pour le projet serviront notamment à aider à financer cet
abonnement annuel.

## Liens

- Présentation : <https://growthcroissance.github.io/capote/>
- Code consultable : <https://github.com/growthcroissance/capote>
- Versions officielles : <https://github.com/growthcroissance/capote/releases>
- Politique de sécurité : <https://github.com/growthcroissance/capote/security>
- GROWTH Croissance : <https://www.growth-croissance.com/>

## Message proposé à MacGeneration

Destinataire vérifié le 22 août 2026 : `redaction@macgeneration.com`, adresse
encore utilisée par la rédaction dans un article publié en janvier 2026.
Page de contact officielle : <https://www.macg.co/contact>.

**Objet : À découvrir — Capote garde un MacBook éveillé, même refermé**

Bonjour la rédaction,

Je vous signale Capote, un petit utilitaire français pour macOS qui permet
d’empêcher temporairement la veille d’un MacBook lorsque son capot est fermé.

L’application vit dans la barre des menus et peut maintenir la session pendant
une durée déterminée, jusqu’à une heure donnée, tant qu’une application
fonctionne ou tant qu’un téléchargement progresse. Elle rétablit ensuite
automatiquement la veille et comporte une protection thermique qui interrompt
la session si macOS signale une température sérieuse ou critique.

Capote est native, compatible Apple Silicon et Intel, gratuite, sans compte et
sans collecte de données. Le mot de passe administrateur est géré directement
par macOS et n’est jamais lu ni conservé.

Le projet reste pour l’instant à diffusion limitée et je n’ai pas encore
souscrit au programme Apple Developer. L’application n’est donc pas notariée et
macOS demande une ouverture manuelle lors du premier lancement. Comme elle agit
sur un réglage système, j’ai choisi de rendre son code entièrement consultable
afin que chacun puisse auditer son fonctionnement. Il s’agit d’un logiciel
propriétaire dont la licence autorise la consultation et la compilation locale
de vérification, et non d’un projet open source.

Je développe également un compagnon iOS pour Capote. Sa distribution
nécessitera cette fois une adhésion à l’Apple Developer Program ; les dons
facultatifs au projet m’aideront notamment à financer cet abonnement annuel.

Présentation : <https://growthcroissance.github.io/capote/>

Téléchargement : <https://github.com/growthcroissance/capote/releases/latest>

Code consultable : <https://github.com/growthcroissance/capote>

Si le sujet vous intéresse, je peux vous transmettre des captures, une courte
démonstration et répondre aux questions techniques.

Bien cordialement,

Benjamin Farrudja

## Éléments à joindre ou à rendre accessibles

- icône haute définition de Capote ;
- deux captures lisibles du menu de l’application ;
- une courte vidéo montrant le choix d’une session et sa restauration ;
- lien vers la release exacte proposée au test ;
- sommes SHA-256 et attestations de provenance de cette release ;
- rappel visible de l’avertissement thermique et du statut non notarié.

Ne pas envoyer le binaire en pièce jointe et ne pas employer « open source » :
le code est visible pour audit sous une licence propriétaire.
