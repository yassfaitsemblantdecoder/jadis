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
