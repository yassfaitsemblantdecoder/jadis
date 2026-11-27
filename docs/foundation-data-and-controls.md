# Jadis — modèle de scolarité et contrôles Foundation First

## Décision DATA-01

La migration 007 prépare un modèle canonique dans PostgreSQL. Les nouvelles tables sont dans `jadis_private`, avec RLS et sans droits directs pour les rôles clients. La bêta continue d’utiliser ses tables et RPC existantes. La migration ne copie aucune donnée et ne change aucun parcours utilisateur.

| Table | Responsabilité |
| --- | --- |
| `institutions` | Identifiant interne stable, nom courant, type et date de fermeture éventuelle. |
| `institution_identifiers` | Identifiant externe unique par source, date d’enregistrement et rattachement à l’établissement canonique. Un identifiant seul ne prouve ni identité ni scolarité. |
| `institution_names` | Autres noms et noms historiques, avec une période optionnelle dont la borne de fin est exclusive. |
| `cohorts` | Année de rentrée, niveau et section facultative au sein d’un établissement. |
| `attendance` | Scolarité déclarée d’un titulaire de profil. L’année et l’établissement sont obligatoires. Une classe renseignée doit appartenir à ce même établissement et à cette même année. La suppression du profil supprime ses déclarations. |

L’année désigne la rentrée de l’année scolaire. Une période civile de `journeys` ne suffit donc pas à déduire une classe ni une année de rentrée. Une déclaration avec classe inconnue peut être complétée après confirmation du titulaire. Les dates et niveaux importés doivent être normalisés et contrôlés avant écriture. La modélisation des campus, formations, fusions et fermetures avec succession viendra après validation des référentiels.

### Passage au modèle canonique

1. Valider les référentiels DATA-02 et constituer le registre des identifiants et des alias DATA-03 à partir de données autorisées.
2. Sur une copie synthétique, établir la correspondance entre `schools`, `classes`, `memberships`, `journeys` et `beta_school_entries`. Mettre de côté les identifiants ambigus, les incohérences d’année et les doublons. Demander confirmation pour les parcours incertains.
3. Comparer les résultats du matching ancien et nouveau, par paires consentantes, et vérifier les suppressions et les blocages. Prévoir une seule source d’écriture pendant la bascule.
4. Pour 007 seule, le retour consiste à conserver les nouvelles tables inaccessibles. Sur une base jetable ou une base confirmée vide, on peut retirer les tables ajoutées dans l’ordre `attendance`, `cohorts`, `institution_names`, `institution_identifiers`, `institutions`. Une fois des données écrites, établir un plan de conservation et de retour avant tout retrait.

## ARCH-02 et sécurité

Exécuter `bash scripts/test-db.sh`. Le script crée un PostgreSQL 16 sans port publié, sans réseau et avec un stockage temporaire. Il charge les migrations dans l’ordre, exécute les assertions avec des comptes fictifs, puis restaure le schéma et les lots d’annuaire fictifs dans une seconde base et rejoue les mêmes assertions. La CI propose le même contrôle sur les branches et PR.

Les assertions couvrent les permissions du rôle anonyme, le cloisonnement des tables canoniques, la visibilité limitée au propriétaire, l’utilisateur hors bêta, l’absence de correspondance sans scolarité commune ou sans consentement, le blocage dans les deux sens et la suppression des déclarations avec le compte. Elles vérifient aussi le refus d’une déclaration dupliquée sans classe et le rattachement d’une classe à son établissement.

Le banc reproduit les tables et la fonction d’identité PostgreSQL nécessaires aux migrations. Avec `--rest`, un PostgREST isolé vérifie l’exposition du schéma public, les rôles anonyme et authentifié, la découverte, l’acceptation d’une reconnexion, la messagerie et le blocage. Les jetons de test sont signés localement. Avec `--auth`, le banc ajoute Supabase Auth et un récepteur SMTP local pour l’inscription, les invitations, les jetons et la récupération de compte. Les paramètres du projet hébergé, les emails via le prestataire et la restauration du service complet restent à vérifier. Les limites de débit et les opérations concurrentes de reconnexion réclament des scénarios dédiés.

## Architecture et exploitation

- Le navigateur sert le prototype et appelle Auth et l’API Supabase pour la bêta. Les contrôles d’accès s’appliquent côté PostgreSQL. Le modèle canonique sert de cible interne et ne crée pas de nouvel endpoint.
- Le futur import d’annuaire doit recevoir des données d’établissements, avec contrôles de provenance, reprise et quarantaine. Éviter l’envoi de termes de recherche personnels aux fournisseurs d’annuaires.
- Parcours de validation infra à documenter avant un pilote réel. Recenser projet, région, hébergeur, propriétaires et administrateurs. Valider sauvegardes, restauration isolée, objectifs de reprise, quotas, alertes et procédure d’incident. Limiter les accès de CI au dépôt et utiliser des environnements et comptes de test dédiés.

## Décisions réglementaires à instruire avant un pilote réel

| Dossier | Preuve attendue |
| --- | --- |
| Responsable du traitement | Identité et coordonnées de l’entité qui décide des finalités, rôles des prestataires, contrats, localisation et transferts. |
| Finalités et bases légales | Inventaire des traitements d’inscription, parcours, découverte, messagerie et modération. Choix documenté d’une base légale par finalité et retrait effectif de l’opt-in de visibilité. |
| Information et droits | Notice avant collecte, procédure d’accès, export, rectification et effacement. Vérification des effets sur les sessions, sauvegardes et données conservées pour la modération. |
| Conservation | Durées validées pour comptes inactifs, invitations, messages, signalements, journaux et sauvegardes, avec des procédures de purge testées. |
| Protection des personnes | Évaluation du besoin d’AIPD, politique adulte, mesures proportionnées de prévention des abus, suivi des signalements et procédure de réponse aux violations. |

Références pour instruire ces décisions. [RGPD, articles 5, 6, 12–22, 25, 28 et 30–35](https://eur-lex.europa.eu/eli/reg/2016/679/oj) · [CNIL, analyse d’impact relative à la protection des données](https://www.cnil.fr/fr/RGPD-analyse-impact-protection-des-donnees-aipd).
