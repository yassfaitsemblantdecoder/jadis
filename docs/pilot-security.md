# Sécurité du pilote Jadis

Revue du 27 novembre 2026 sur le commit `fad53f3`. Les vérifications ont utilisé exclusivement les comptes et données synthétiques du dépôt sur un réseau Docker interne, sans port publié. La décision d’ouvrir le pilote dépend des preuves sur l’environnement hébergé et de la désignation des personnes responsables.

## Périmètre d’accès vérifié

| Surface | Règle du pilote | Vérification sur le banc isolé |
| --- | --- | --- |
| Profil, parcours scolaire et frise | Le titulaire gère ses données. L’accès au parcours exige l’adhésion à la bêta. | Accès anonyme et non-membre refusé ou vide selon la route. Lecture, modification et suppression de l’étape d’un autre membre refusées. |
| Découverte et recherches privées | La découverte exige les consentements et les critères communs. Les recherches sauvegardées appartiennent au titulaire. | Correspondance consentie, absence de correspondance hors périmètre, recherches invisibles aux autres membres et effacement avec l’étape. |
| Retrouvailles, messages et blocages | Les messages exigent une demande acceptée. Un blocage masque la relation dans les deux sens. | Demande, acceptation et échange de messages fictifs. Liste vide chez les deux participants après blocage. |
| Capsules et photos | Accès sur invitation acceptée. Chaque auteur peut retirer ses propres contributions. | Accès interdit à un tiers et à un invité en attente. Lecture des contributions, refus des dimensions photo hors limites, disparition des contributions après départ et fermeture de l’accès après blocage. |
| Invitation et récupération | Email confirmé, invitation à usage unique et récupération par lien Auth. | Confirmation via Mailpit, refus de réemploi de l’invitation, réinitialisation et rejet de l’ancien mot de passe. Le renouvellement est refusé après déconnexion. |
| Export et suppression de compte | Export du titulaire et suppression après confirmation explicite et authentification récente par mot de passe. | Export d’un compte sans données de l’autre, refus de supprimer avec le seul jeton de récupération, suppression acceptée après confirmation et refus des anciens accès à l’export et à la frise. |
| Signalements et administration | Les membres peuvent envoyer un signalement. L’exploitant attribue sa lecture et son traitement à des personnes autorisées. | Les migrations accordent l’insertion aux membres concernés. La prise en charge opérationnelle reste à exercer. |

## Preuves de développement

- `bash scripts/test-db.sh --auth` a terminé avec succès. Le banc a rejoué les 14 migrations, restauré la base de test, vérifié les permissions via PostgREST et exécuté les parcours Supabase Auth avec Mailpit.
- Un contrôle complémentaire des catalogues PostgreSQL a confirmé la sécurité au niveau des lignes sur 29 tables applicatives, dont 18 dans le schéma interne. Le rôle anonyme ne dispose d’aucun droit direct sur ces tables. Le rôle authentifié ne dispose d’aucun droit direct sur les tables du schéma interne. Les neuf RPC du schéma public s’exécutent avec les droits de l’appelant. Les neuf fonctions privilégiées du schéma interne fixent un chemin de recherche vide.
- Une recherche ciblée dans les 100 objets texte des 48 commits accessibles n’a remonté aucun marqueur parmi les cinq familles recherchées. Clés privées, jetons GitHub, identifiants de clés AWS, clés Supabase secrètes et JWT. La vérification des paramètres hébergés, des journaux CI et des autres formats de secrets reste à compléter.
- Deux workflows utilisent encore des références d’actions par version majeure. Le job base de données fixe sa révision de `checkout`. Le workflow Pages accorde actuellement ses droits de publication à tous ses jobs. Ces réglages entrent dans la revue de la chaîne de livraison avant l’ouverture.

## Décision avant l’ouverture

| Priorité | Vérification à réaliser sur un environnement pilote isolé | Preuve à joindre | Responsable à désigner |
| --- | --- | --- | --- |
| SEC-01 | Comparer les schémas exposés, les rôles, les droits par défaut et les fonctions du projet hébergé avec le banc. Vérifier aussi l’accès administratif et le périmètre des médias. | Résumé daté des droits et contrôle des rôles anonyme, authentifié non-membre, membre et opérateur sur des données fictives. | Exploitation Supabase |
| SEC-02 | Vérifier l’inscription sur invitation et les paramètres d’ouverture d’Auth. Tester l’envoi SMTP auprès du prestataire et les redirections HTTPS du site pilote, ainsi que la durée des jetons, le renouvellement, la récupération et la MFA des administrateurs. | Confirmation et récupération reçues sur des boîtes de test, redirections consignées, politique de session et preuve MFA sans jetons ni secrets. Mesurer la durée éventuelle d’accès d’un jeton déjà émis après déconnexion. | Exploitation Auth |
| SEC-03 | Fixer les révisions des actions, limiter les droits de publication au job de déploiement et vérifier les protections de branche et d’environnement. Terminer le contrôle des secrets de CI et d’hébergement sans recopier leurs valeurs. | Revue du workflow et des règles GitHub, liste des personnes et services autorisés à publier. | Référent CI et publication |
| SEC-04 | Confirmer les limites d’usage sur l’environnement pilote. Compléter la vérification des retraits de consentement, états obsolètes côté navigateur et opérations concurrentes de blocage, d’acceptation ou de sortie d’une capsule. | Résultats par parcours et état final attendu. Aucune donnée de tiers visible après révocation, y compris après rafraîchissement. | Référent sécurité et produit |
| TRUST-02 / OPS-01 | Traiter un signalement fictif avec un opérateur nommé. Exercer la suspension du flux concerné, la restauration isolée et l’escalade d’un incident. | Résultat de l’exercice, droits d’accès aux preuves, durée de restauration et décisions de reprise. | Exploitation et modération |

### Circuit d’incident

1. Consigner l’heure, le signal, le périmètre connu et la personne responsable dans un emplacement à accès restreint. Garder les secrets et données privées hors du dépôt et des tickets publics.
2. Suspendre le flux concerné depuis le plan d’exploitation validé. Préserver les éléments utiles, limiter leur accès et décider si une rotation de secret ou une révocation de session est nécessaire.
3. Faire analyser la gravité et le risque pour les personnes par l’exploitant et le responsable du traitement. Rejouer les contrôles avant rétablissement, vérifier les alertes et consigner la décision.

Les comptes réels attendent l’exercice sur le projet pilote et la validation des preuves de sécurité, de protection des données et de modération. [Dossier avant pilote](pilot-readiness.md) · [Gates Foundation First](foundation-first.md)
