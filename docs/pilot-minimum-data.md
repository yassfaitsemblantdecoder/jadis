# Modèle de données minimal du pilote Jadis

Périmètre cible proposé pour une recette sur comptes fictifs. Le parcours testé va de l’activation sur invitation à une retrouvaille entre deux personnes ayant déclaré le même établissement et une année scolaire commune. Les choix de collecte, de conservation et d’ouverture restent à valider dans le [dossier opérateur](pilot-privacy.md).

## Matrice de collecte

| Périmètre | Statut cible | Données retenues et finalité |
| --- | --- | --- |
| Connexion et activation | Indispensable | Email de connexion et de récupération, vérification et identifiant interne gérés par Auth. Mot de passe traité par Auth. Code d’invitation à usage unique, échéance et état de consommation. Déclaration de majorité à l’activation, sans date de naissance collectée. |
| Profil | Indispensable après activation | Pseudonyme choisi, identifiant du compte et préférence générale de découverte désactivée par défaut. L’application ne demande pas de nom civil. |
| Étape de scolarité | Indispensable pour créer une étape | Identifiant du titulaire côté serveur, référence à un établissement approuvé et année de rentrée scolaire. Préférence de découverte de l’étape désactivée par défaut. Le libellé se lit dans le référentiel et la commune de l’établissement ne se recopie pas dans le parcours. |
| Retrouvaille et sécurité | Indispensable pour la fonctionnalité concernée | Deux identifiants, décision de demande et horodatages nécessaires au suivi. Pour bloquer, conserver la paire concernée. Pour signaler, limiter la fiche au type de problème, au contexte nécessaire à son traitement et au motif saisi, avec accès habilité. Limiter les enregistrements de sécurité et d’exploitation à ce qui sert au contrôle d’accès, à la reprise et à la preuve d’un incident. |
| Messagerie | Facultatif après acceptation mutuelle | Texte, expéditeur, fil et date. Aucun champ de contact à remplir pour se reconnecter. |
| Sauvegarde d’une recherche | Facultatif si retenu dans le pilote | Référence à une étape du titulaire et année recherchée. La suppression de l’étape retire la recherche liée. Une recherche simple peut être exécutée sans sauvegarde. |
| Enrichissement et mémoires partagées | Hors pilote minimal | Niveau, section, classe, autres lieux, capsules, photos, légendes et pièces jointes. Prévoir leur examen avant d’élargir le périmètre. |
| Identification et contacts supplémentaires | Hors pilote minimal | Date de naissance, nom civil ou ancien nom, téléphone, adresse personnelle, géolocalisation, contacts importés et données concernant les élèves, enseignants ou autres tiers. |

## Annuaire canonique du pilote

Pour la première admission du pilote, retenir une liste explicite de **1 à 25 établissements** approuvés par le responsable données. Restreindre cette première sélection aux écoles, collèges et lycées indiqués comme ouverts dans l’Annuaire de l’éducation. Les seuls champs métier canoniques sont **nom, type et UAI**. Un UUID interne relie l’établissement au parcours. [Critères d’annuaire](pilot-directory.md)

Conserver en préparation la commune, le statut de la source et les éléments nécessaires au contrôle du lot, dont l’URL, l’éditeur, la date publiée, la licence et l’empreinte. La commune sert à vérifier les homonymes. Une UAI conflictuelle, une correspondance incertaine ou un candidat incomplet reste en revue. Les établissements fermés et le supérieur restent en préparation. Le rapprochement institutionnel ne vérifie ni l’identité ni la scolarité d’une personne. [Résultats de validation](directory-source-validation.md)

## Écarts observés dans le dépôt

| Collecte ou comportement actuel | Cible avant recette du pilote minimal |
| --- | --- |
| Le profil accepte un nom affiché ou un pseudonyme. La frise prend un type et un nom de lieu libres, une commune et deux années civiles obligatoires. | Inviter à choisir un pseudonyme. Pour l’étape scolaire, sélectionner une référence approuvée et saisir une année de rentrée unique. Conserver la distinction entre année scolaire et période civile. [Profil et frise](../beta.html) · [Frise actuelle](../supabase/migrations/010_private_timeline.sql) |
| Le formulaire d’établissement historique remplit `directory_id`, nom, commune, année, niveau et section dans `beta_school_entries`. Le build peut activer la recherche externe, désactivée par défaut. | Garder le flux externe désactivé dans le pilote. Tester une sélection sur l’annuaire de Jadis et une écriture fondée sur la référence, sans copie des champs institutionnels dans le parcours. [Écriture actuelle](../beta.js) · [Modèle canonique](../supabase/migrations/007_canonical_attendance.sql) |
| La base possède des tables privées de staging et des tables canoniques. La migration 015 prévisualise les candidats et la migration 016 applique une liste explicite de 25 UAI maximum par admission. | Faire approuver la sélection initiale, puis vérifier que la version candidate lit les établissements admis. [Prévisualisation](../supabase/migrations/015_directory_promotion_preview.sql) · [Admission](../supabase/migrations/016_directory_pilot_admission.sql) |
| Les capsules, photos et lieux hors scolarité existent dans la bêta de développement. Le signalement actuel enregistre l’auteur, la cible éventuelle, un motif libre et une date. | Maintenir les fonctions hors périmètre inaccessibles dans la version candidate et vérifier aussi leurs points d’accès. Borner l’usage du motif et valider le suivi du signalement par un opérateur. [Bêta existante](product-beta.md) · [Signalements](../supabase/migrations/001_foundation.sql) |

## Preuves à recueillir sur une cible isolée

1. Vérifier le manifeste d’admission et l’unicité des UAI. Un lot de 26, une référence hors liste et une ligne conflictuelle doivent être refusés. Rejouer le même manifeste et vérifier la stabilité des identifiants et des décomptes.
2. Vérifier les formulaires, les corps de requête et les écritures avec des comptes fictifs. Les champs hors pilote restent absents à l’écran et refusés au point d’écriture. Une recherche ne transmet ni saisie ni données de profil à un annuaire externe. L’email ne figure pas dans les réponses de découverte.
3. Vérifier les accès avec deux profils invités, un compte non invité et une session anonyme. Une étape non activée, le retrait de visibilité ou un blocage empêche le rapprochement. Une étape supprimée entraîne la disparition de sa recherche enregistrée si cette option est proposée.
4. Vérifier l’export et l’effacement sur les données réellement collectées. La procédure opérateur doit distinguer données actives, signalements, journaux et sauvegardes. Faire valider chaque durée par le responsable du traitement et tester les échéances et les purges qu’il a approuvées. [Recette du pilote](pilot-product.md) · [Droits et conservation](pilot-privacy.md)
