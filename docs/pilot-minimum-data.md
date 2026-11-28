# Modèle de données minimal du pilote Jadis

Périmètre cible proposé pour une recette sur comptes fictifs. La version scolaire en recette relie chaque étape à un établissement admis et à une année de rentrée. La découverte entre deux comptes fictifs se vérifie dans le banc API. Les choix de collecte, de conservation et d’ouverture restent à valider dans le [dossier opérateur](pilot-privacy.md).

## Matrice de collecte

| Périmètre | Statut cible | Données retenues et finalité |
| --- | --- | --- |
| Connexion et activation | Indispensable | Email de connexion et de récupération, vérification et identifiant interne gérés par Auth. Mot de passe traité par Auth. Code d’invitation à usage unique, échéance et état de consommation. Déclaration de majorité à l’activation, sans date de naissance collectée. |
| Profil | Indispensable après activation | Pseudonyme choisi, identifiant du compte et préférence générale de découverte désactivée par défaut. L’application ne demande pas de nom civil. |
| Étape de scolarité | Indispensable pour créer une étape | Identifiant du titulaire côté serveur, référence à un établissement approuvé et année de rentrée scolaire. Préférence de découverte de l’étape désactivée par défaut. Le libellé se lit dans le référentiel et la commune de l’établissement ne se recopie pas dans le parcours. |
| Retrouvaille et sécurité | Indispensable pour la fonctionnalité concernée | Deux identifiants, décision de demande et horodatages nécessaires au suivi. Pour bloquer, conserver la paire concernée. Pour signaler, limiter la fiche au type de problème, au contexte nécessaire à son traitement et au motif saisi, avec accès habilité. Limiter les enregistrements de sécurité et d’exploitation à ce qui sert au contrôle d’accès, à la reprise et à la preuve d’un incident. |
| Messagerie | Facultatif après acceptation mutuelle | Texte, expéditeur, fil et date. Aucun champ de contact à remplir pour se reconnecter. |
| Sauvegarde d’une recherche | Hors de la première version minimale | Une recherche scolaire simple peut être exécutée sans enregistrement supplémentaire. |
| Enrichissement et mémoires partagées | Hors pilote minimal | Niveau, section, classe, autres lieux, capsules, photos, légendes et pièces jointes. Prévoir leur examen avant d’élargir le périmètre. |
| Identification et contacts supplémentaires | Hors pilote minimal | Date de naissance, nom civil ou ancien nom, téléphone, adresse personnelle, géolocalisation, contacts importés et données concernant les élèves, enseignants ou autres tiers. |

## Annuaire canonique du pilote

Pour la première admission du pilote, retenir une liste explicite de **1 à 25 établissements** approuvés par le responsable données. Restreindre cette première sélection aux écoles, collèges et lycées indiqués comme ouverts dans l’Annuaire de l’éducation. Les seuls champs métier canoniques sont **nom, type et UAI**. Un UUID interne relie l’établissement au parcours. [Critères d’annuaire](pilot-directory.md)

Conserver en préparation la commune, le statut de la source et les éléments nécessaires au contrôle du lot, dont l’URL, l’éditeur, la date publiée, la licence et l’empreinte. La commune sert à vérifier les homonymes. Une UAI conflictuelle, une correspondance incertaine ou un candidat incomplet reste en revue. Les établissements fermés et le supérieur restent en préparation. Le rapprochement institutionnel ne vérifie ni l’identité ni la scolarité d’une personne. [Résultats de validation](directory-source-validation.md)

## Modes de la bêta

| Surface | Mode scolaire minimal |
| --- | --- |
| Profil et parcours | Le profil propose un pseudonyme. L’étape scolaire enregistre la référence canonique, l’année de rentrée et la préférence de découverte. Le catalogue se limite aux établissements admis. [Migration du parcours](../supabase/migrations/017_pilot_school_journey.sql) |
| Découverte | Les deux profils et les deux étapes doivent avoir activé la découverte. La correspondance exige le même établissement et la même année, et les blocages s’appliquent. Le titulaire peut retirer son accord ou supprimer son étape même si l’établissement sort du catalogue. Un retrait de la découverte empêche de nouvelles correspondances et demandes. Les retrouvailles déjà établies se gèrent depuis leur espace dédié. |
| Périmètre de collecte | Le build minimal désactive l’annuaire externe et masque les anciens parcours, capsules et recherches enregistrées. Sur la cible isolée, appliquer la restriction serveur avant trafic pour que ces opérations soient aussi refusées côté API. [Activation serveur](../supabase/import/enable_pilot_school_only.sql) |
| Exercice des droits | L’export inclut les étapes scolaires du titulaire et la suppression du compte les retire par cascade. L’exercice de recette couvre les commandes avec de vrais jetons sur des comptes fictifs. |

## Preuves à recueillir sur une cible isolée

1. Vérifier le manifeste d’admission et l’unicité des UAI. Un lot de 26, une référence hors liste et une ligne conflictuelle doivent être refusés. Rejouer le même manifeste et vérifier la stabilité des identifiants et des décomptes.
2. Vérifier les formulaires, les corps de requête et les écritures avec des comptes fictifs. Les champs hors pilote restent absents à l’écran et refusés au point d’écriture. Une recherche ne transmet ni saisie ni données de profil à un annuaire externe. L’email ne figure pas dans les réponses de découverte.
3. Vérifier les accès avec deux profils invités, un compte non invité et une session anonyme. Une étape non activée, le retrait de visibilité ou un blocage empêche le rapprochement. Une étape supprimée disparaît de l’export et des futures correspondances.
4. Vérifier l’export et l’effacement sur les données réellement collectées. La procédure opérateur doit distinguer données actives, signalements, journaux et sauvegardes. Faire valider chaque durée par le responsable du traitement et tester les échéances et les purges qu’il a approuvées. [Recette du pilote](pilot-product.md) · [Droits et conservation](pilot-privacy.md)
