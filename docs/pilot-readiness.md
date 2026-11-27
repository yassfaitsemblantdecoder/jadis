# Contrôles avant un pilote Jadis

## Flux et points de contrôle

| Flux | Contrôle à retenir | Preuve attendue dans l’environnement de test |
| --- | --- | --- |
| Navigateur vers Auth et PostgREST | Clé publique côté navigateur, jetons à durée limitée, schéma REST limité à `public`. | Le banc isolé vérifie la confirmation d’email, l’invitation à usage unique, le renouvellement et sa révocation après déconnexion, ainsi que la récupération du mot de passe. Vérifier sur l’instance de pilote les expirations, le comportement après suppression et les paramètres du fournisseur SMTP. |
| PostgREST vers PostgreSQL | RLS, droits explicites et accès aux parcours limité au titulaire. Découverte sur opt-in et filtre de blocage dans les deux sens. | Rejouer les tests du dépôt, puis vérifier les mêmes droits depuis une instance Supabase isolée avec ses valeurs par défaut. |
| Annuaire officiel vers PostgreSQL | Export institutionnel, empreinte et provenance, préparation privée, revue avant promotion. | Rapprocher les décomptes de chaque lot, examiner les lignes en conflit et vérifier les conditions de retrait d’un lot. |
| Opérateur vers administration | Comptes nominatifs, MFA, accès de secours documenté et suivi des changements. | Vérifier qui peut publier, administrer la base, lire les signalements et restaurer une sauvegarde. |

## Banc de test avant pilote

Lancer `bash scripts/test-db.sh --auth`. Le test lance PostgreSQL, PostgREST, Supabase Auth et un récepteur SMTP Mailpit sur un réseau Docker interne sans port publié. Deux comptes fictifs reçoivent leurs emails dans Mailpit. Un jeton réellement émis par Auth est utilisé pour vérifier l’adhésion à la bêta. Le banc est également lancé par le job base de données de la CI.

Le test prouve le chemin SMTP local. La délivrabilité via un prestataire, les liens de retour vers le site hébergé et les paramètres du projet Supabase de pilote restent à vérifier avec leur configuration réelle. La déconnexion invalide le renouvellement testé. Des jetons d’accès déjà émis peuvent rester utilisables jusqu’à leur expiration.

## Exercice d’exploitation

1. Utiliser un environnement Supabase isolé et des comptes fictifs. Relever la version PostgreSQL, les paramètres Auth, les schémas exposés et les rôles.
2. Capturer une sauvegarde d’essai, restaurer sur une cible isolée et mesurer la durée. Comparer schéma, décomptes et accès après restauration. Le banc actuel vérifie le schéma et les lots d’annuaire fictifs sur PostgreSQL.
3. Tester la suspension des inscriptions et des imports, la rotation d’un secret de test, le rétablissement et les alertes. Faire valider les délais acceptables de perte de données et de reprise par l’exploitant.
4. En cas d’incident, consigner le début et le périmètre, suspendre le flux concerné, limiter l’accès aux éléments conservés et faire évaluer le risque pour les personnes par le responsable du traitement. Répéter la procédure sur données fictives.

## Décisions à faire valider

- Renseigner le responsable du traitement et le contact des personnes. Attribuer nominativement les fonctions d’administration et de modération.
- Valider les bases légales et la notice par finalité. Fixer les durées de conservation des parcours, comptes, messages, signalements, journaux et sauvegardes. Tester le retrait de visibilité, l’accès, la rectification et l’effacement.
- Documenter les sous-traitants, les transferts et l’évaluation du besoin d’AIPD. Prévoir un circuit de signalement et de traitement des incidents. [RGPD, articles 28 à 35](https://eur-lex.europa.eu/eli/reg/2016/679/oj) · [Critères et listes AIPD de la CNIL](https://www.cnil.fr/fr/RGPD-analyse-impact-protection-des-donnees-aipd)

Le [parcours de la bêta](product-beta.md) décrit les fonctionnalités disponibles en développement et les données incluses dans les commandes de compte.

Les preuves de développement et les décisions qui autorisent un pilote doivent être consignées avant d’ouvrir les inscriptions.
