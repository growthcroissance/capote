# Politique de sécurité

## Signaler une vulnérabilité

Merci de ne pas publier les détails d’une vulnérabilité non corrigée dans une
issue, une discussion ou une pull request publique.

Utilisez le bouton **Report a vulnerability** de l’onglet **Security** du dépôt
pour créer un rapport privé :

<https://github.com/growthcroissance/capote/security/advisories/new>

Indiquez si possible la version concernée, la version de macOS, les étapes de
reproduction, l’impact observé et toute mesure temporaire connue. Aucun secret,
mot de passe administrateur ou donnée personnelle ne doit être joint.

Si le formulaire privé n’est pas encore disponible, ouvrez seulement une issue
sans détail technique afin de demander un canal privé.

## Périmètre

Les rapports concernant l’exécution de commandes privilégiées, la restauration
de `SleepDisabled`, les contrôles thermiques, la chaîne de publication ou une
différence entre le code tagué et l’archive distribuée sont prioritaires.

Sont également prioritaires les contournements du jumelage iPhone, la réutilisation
d’une commande expirée, l’usurpation d’un appareil révoqué, l’exposition d’une clé
du Trousseau ou l’acceptation par le daemon root d’un client XPC non signé par
l’équipe attendue.

Les rapports de sécurité sont les bienvenus. La consultation et l’audit du code
restent soumis à la [licence propriétaire d’audit](LICENSE.md).
