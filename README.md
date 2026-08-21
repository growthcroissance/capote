# Capote

Capote est un petit utilitaire personnel pour macOS. Il vit dans la barre
des menus et permet d'empêcher la mise en veille lorsque le capot d'un MacBook
est fermé.

L'application pilote l'option système `pmset -a disablesleep`. macOS demande une
autorisation administrateur au démarrage d'une session. Le mot de passe n'est ni
lu ni conservé par l'application.

## Fonctionnalités

- lecture de l'état système réel `SleepDisabled` ;
- activation après avertissement thermique et autorisation administrateur ;
- sessions de 5 à 55 minutes et de 1 à 24 heures ;
- session jusqu'à une date et une heure choisies ;
- session tant qu'une application sélectionnée est en cours d'exécution ;
- session pendant l'évolution d'un fichier de téléchargement, avec délai de fin ;
- restauration automatique par un helper privilégié embarqué ;
- restauration immédiate si macOS signale un état thermique sérieux ou critique ;
- notification locale expliquant l’arrêt de sécurité thermique ;
- restauration explicite de la veille ;
- action « rétablir la veille et quitter ».

Les sessions limitées continuent même si Capote est quittée et rétablissent la
veille lorsque leur condition prend fin. Une session sans limite reste active
jusqu'à une restauration explicite. Utilisez « Rétablir la veille et quitter »
lorsque vous avez terminé.

La protection thermique est surveillée par le helper, y compris lorsque Capote
est quittée. Si Capote reste ouverte, la notification locale est présentée dès
l’arrêt de sécurité. Si elle a été quittée, le motif est affiché et notifié à
son prochain lancement. Cette protection ne remplace pas une ventilation
adaptée et ne doit jamais être contournée.

> **Attention :** un Mac actif avec le capot fermé peut chauffer fortement. Ne
> l'utilisez jamais dans un sac, une housse fermée ou sans ventilation adaptée.

## Développement

Prérequis : macOS 14 ou ultérieur et les outils de développement Apple.

```sh
./scripts/test.sh
./scripts/build-app.sh
```

Le paquet Swift reste compatible avec `swift test` lorsque Xcode ou des Command
Line Tools cohérents sont installés. Les scripts du projet sélectionnent aussi
un SDK de repli compatible avec l'outillage présent sur la machine de
développement.

Le dépôt suit Git Flow. Les règles de travail, de validation et de sécurité sont
décrites dans [AGENTS.md](AGENTS.md) et [CONTRIBUTING.md](CONTRIBUTING.md). Les
versions publiées sont consignées dans [CHANGELOG.md](CHANGELOG.md).

## Construire l'application

```sh
./scripts/build-app.sh
```

Le bundle est créé dans `dist/Capote.app`. Il est signé localement de façon
ad hoc pour un usage personnel. Pour l'installer, déplacez-le manuellement dans
le dossier Applications.

Une archive `dist/Capote-0.4.0.zip` est également produite et vérifiée après
extraction. Elle est recommandée pour mettre à jour une copie déjà placée dans
Applications, car certains dossiers synchronisés réappliquent des attributs
Finder aux bundles `.app`.

## Implémentation et limites

`disablesleep` est reconnu par `/usr/bin/pmset` et son état courant est exposé par
`pmset -g live` sous le nom `SleepDisabled`. L'option reste toutefois absente de
la page de manuel locale de `pmset` sur la version de macOS utilisée pour le
développement. Elle doit donc être considérée comme non documentée et susceptible
d'évoluer avec macOS.

Le helper de session n'accepte que quatre modes strictement validés : durée,
processus, fichier en évolution et durée indéfinie. Les chemins sont transmis en
base64 afin de ne jamais être interprétés comme des commandes shell. Le fichier
de retour thermique est précréé par Capote puis ouvert sans suivre les liens
symboliques et uniquement pour l'utilisateur qui a lancé la session.
