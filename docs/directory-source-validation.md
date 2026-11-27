# DATA-02 — Validation des sources d’annuaire

Depuis la racine, lancer `python3 scripts/check-directory-sources.py` pour vérifier les métadonnées, les champs et deux pages de cinq lignes par source. Ajouter `--exports` pour comparer les identifiants sur les exports JSON complets. La commande conserve les identifiants uniquement en mémoire et affiche des décomptes. Elle signale une source inaccessible, un champ manquant ou un écart entre le nombre annoncé et le nombre exporté.

## Observation du 27 novembre 2026

| Source | État des identifiants | Couverture et correspondance |
| --- | --- | --- |
| [Annuaire de l’éducation](https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/) | 68 548 lignes, 68 462 UAI distinctes, soit 86 lignes au-delà de la première occurrence. | Mapper `identifiant_de_l_etablissement` et `nom_etablissement`. Comparer les autres champs des lignes répétées avant de trancher entre doublons équivalents et établissements ambigus. |
| [Établissements fermés](https://data.education.gouv.fr/explore/dataset/fr-en-etablissements-fermes/) | 42 810 lignes et autant d’UAI distinctes. | Mapper `numero_uai`, les noms, `date_ouverture` et `date_fermeture`. Les dates de fermeture renseignées vont du 18 janvier 1978 au 8 novembre 2026. Ces bornes ne garantissent pas l’exhaustivité historique. |
| [Principaux établissements du supérieur](https://data.enseignementsup-recherche.gouv.fr/explore/dataset/fr-esr-principaux-etablissements-enseignement-superieur/) | 245 lignes et autant d’identifiants Paysage distincts. Sur 245 valeurs UAI non vides, 19 ont un format différent du motif de 7 chiffres et une lettre. | Mapper `etablissement_id_paysage` et `uo_lib` ou `uo_lib_officiel`. Conserver l’UAI valide et les anciens codes avec leur provenance, après validation. La fiche indique une mise à jour au 26 février 2025 et porte sur les principaux établissements. |

Aucune UAI au format attendu n’était commune à deux exports lors de cette lecture. Ce constat ponctuel ne justifie pas une fusion future sur une seule correspondance d’identifiant. Les totaux ci-dessus proviennent des exports parcourus ligne par ligne.

Les trois catalogues déclarent la Licence Ouverte v2.0. Lors de la réutilisation, conserver au minimum le nom du concédant et la date de mise à jour de la source, ainsi que le lien vers le catalogue pour retrouver cette attribution. [Texte de la Licence Ouverte v2.0 publié par Etalab](https://github.com/etalab/licence-ouverte/blob/48b983e67f2dcbd9a851daa178876b1ec6b49785/LO.md)

## Contrat pour DATA-03

- Préférer les exports avec projection des seuls champs nécessaires. Conserver pour chaque import la source, la date publiée, l’empreinte du contenu et les décomptes.
- Préparer les enregistrements hors des tables principales. Dédupliquer les lignes équivalentes et isoler les conflits à examiner. Conserver les identifiants avec leur namespace et conserver les rapprochements d’alias incertains pour revue.
- Tester qu’une relance du même export ne crée ni doublons ni modifications inutiles. Vérifier la reprise après interruption et le traitement d’un changement de schéma avant d’activer un import régulier.

## Import en zone de préparation

La migration 008 ajoute des lots privés, des candidats et une file de rejet. Chaque lot conserve le catalogue, l’éditeur, la date officielle de mise à jour, l’empreinte SHA-256 du fichier JSON exact et les décomptes. Une relance simultanée ou répétée du même fichier, pour la même source et date, ne crée qu’un lot. L’écriture du lot et de ses lignes est atomique.

`bash scripts/directory-stage-sql.sh SOURCE fichier.json --published-at DATE_ISO --publisher EDITEUR` produit une transaction. Pour les validations, utiliser le banc jetable `bash scripts/test-db.sh --rest`, qui charge trois exports fictifs, vérifie la relance concurrente et restaure la base. Le SQL généré par le script est destiné à une base équipée de la migration 008. Aucun accès à Supabase distant n’est nécessaire au test.

Sur les exports officiels du 27 novembre 2026, la préparation en mémoire a donné les résultats suivants.

| Source | Candidats | Revue ou rejet |
| --- | ---: | --- |
| Annuaire de l’éducation | 68 383 | 1 doublon équivalent écarté, 163 lignes en conflit d’identifiant et 1 champ invalide. |
| Établissements fermés | 42 810 | Tous à revoir, car aucun nom exploitable dans les champs projetés. La date et l’UAI restent disponibles. |
| Enseignement supérieur | 245 | Type éventuellement multivalué normalisé. L’identifiant Paysage est conservé lorsque l’UAI ne peut servir de clé. |

La zone de préparation n’écrit ni dans le modèle canonique ni dans la bêta. Pour promouvoir les candidats, valider les noms manquants, les conflits, les alias d’anciens codes et les rapprochements entre sources. Les lignes rejetées conservent leur numéro et leur raison afin de relire le fichier d’origine. Le retour d’un lot avant promotion consiste à le retirer avec ses lignes en base isolée, après conservation des preuves nécessaires.
