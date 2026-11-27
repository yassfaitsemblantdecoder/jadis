# Jadis — plan de préparation du pilote

## Point de départ

La bêta sur invitation est disponible en développement. La CI du commit `fad53f3` a validé le banc PostgreSQL, PostgREST, Supabase Auth et SMTP avec des comptes fictifs. Le tableau ci-dessous suit les preuves supplémentaires nécessaires sur la version candidate et sur une instance isolée. Les fonctions indiquées sont des propositions à attribuer nominativement. [CI de référence](https://github.com/yassfaitsemblantdecoder/jadis/actions/runs/46074636015)

## Préalable à la recette hébergée

Le build accepte une configuration explicite et la bêta reste fermée sans cible. Le référent technique doit fournir les deux variables de l’instance isolée. [Configuration de la version candidate](pilot-readiness.md#configuration-de-la-version-candidate) Le chef de projet doit vérifier et consigner la destination effective des appels Auth et API avant la création du premier compte fictif dans cette recette.

## Tableau de pilotage

| Chantier | Responsable proposé | Situation | Prochaine action | Preuve pour clôturer |
| --- | --- | --- | --- | --- |
| Sécurité et exploitation | Référent sécurité, avec exploitant Supabase | Contrôles locaux disponibles. Configuration hébergée à vérifier. | Rejouer les parcours d’accès sur une instance isolée, vérifier Auth, SMTP, redirections, rôles et sauvegardes. Préparer suspension et reprise. | Résultats datés par rôle, retour email confirmé, exercice de restauration et de suspension réussi. Détails sensibles conservés en accès restreint. [Dossier sécurité](pilot-security.md) |
| Données | Référent données | Les trois sources et la préparation ont été testées. La promotion reste à décider. | Sélectionner un lot, relire les motifs de rejet, isoler les rapprochements incertains et simuler une promotion sur une cible jetable. | Source, version, empreinte, rapprochement des décomptes, décision sur les lignes litigieuses et retour arrière démontré. [Dossier annuaire](pilot-directory.md) |
| Réglementaire et modération | Responsable du traitement, avec référent modération | Décisions opérateur à instruire. | Désigner les responsables, valider la notice, les bases légales, la conservation, les modalités d’exercice des droits et le circuit de signalement. | Décisions validées et consignées, accès de modération attribués et exercice fictif d’un signalement et d’une demande de droits. [Dossier protection des données](pilot-privacy.md) |
| Produit | Responsable produit | Parcours principaux testés en développement. | Exécuter la recette à deux comptes invités et un compte hors groupe, sur ordinateur et mobile. Relever les échecs et les freins à l’usage. | Recette attachée à la version candidate avec résultat par scénario. Les écarts bloquants sont corrigés ou le périmètre est réduit puis retesté. [Recette produit](pilot-product.md) |
| Coordination | Chef de projet, avec décision du porteur | Version de référence et conditions de passage identifiées. | Consolider la liste des écarts, affecter un responsable et une échéance à chaque action, puis présenter la décision de lancement. | Registre daté, version candidate figée, preuves accessibles aux personnes habilitées et décision de lancement ou de report consignée dans le suivi. |

## Ordre des étapes

1. **Démarrer la vérification isolée.** Figer le commit candidat, vérifier la destination des appels et consigner la cible de test, le responsable désigné et les accès disponibles. Préparer des comptes fictifs, le SMTP de test et les scénarios de retour. L’analyse des sources, la recette produit et le dossier réglementaire avancent en parallèle.
2. **Rejouer la recette candidate.** Vérifier le parcours de l’invitation jusqu’à la suppression du compte sur la configuration candidate. Exercer aussi la restauration, la suspension et le traitement d’un signalement. Un test qui dépend d’un accès indisponible reste ouvert.
3. **Valider le périmètre du pilote.** Fixer les fonctions ouvertes, les personnes pouvant inviter, la taille et la durée du groupe, les horaires de support, les durées de conservation et les modalités de suspension. Si la promotion de l’annuaire est différée, confirmer que la version candidate fonctionne avec le périmètre restant retenu.
4. **Acter le lancement sur invitation.** Le porteur et le responsable du traitement autorisent le périmètre consigné. L’exploitant confirme les droits et la capacité de suspendre. La décision précise la version, les dossiers validés et les risques résiduels acceptés. Si une preuve requise manque, conserver la recette sur données fictives.
5. **Suivre le pilote.** Le chef de projet actualise le registre à chaque revue du pilote. Les incidents de sécurité ou de protection des données sont transmis au responsable désigné. Tout incident laissant planer un doute sur les droits d’accès ou la confidentialité déclenche une suspension et une décision documentée de reprise.

## Décisions à obtenir

| Décision | Décideur proposé | Moment |
| --- | --- | --- |
| Cible Supabase isolée, responsable d’exploitation, SMTP de test et accès nominatifs | Porteur du projet et exploitant | Avant la recette hébergée |
| Lot d’annuaire utilisable, règles d’exclusion et preuve de retrait | Référent données et chef de projet | Avant toute promotion dans le périmètre pilote |
| Responsable du traitement, contact des personnes, règles de conservation et permanence de modération | Porteur du projet et responsable du traitement | Avant toute collecte auprès de participants |
| Taille, durée et fonctions du pilote, capacité de suspension et calendrier de revue | Porteur du projet avec produit, sécurité et modération | Lors de la décision de lancement |

## Première action de coordination

Ouvrir une revue unique de la version candidate. Pour chaque ligne du tableau, inscrire un nom, la prochaine action datée et un lien vers sa preuve. Le point de décision peut alors être programmé à partir de la dernière vérification indispensable, avec un seul registre pour les écarts, leur arbitrage et les conditions de reprise.
