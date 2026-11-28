# Annuaire Jadis — décision de promotion pour le pilote

Le staging DATA-03 est vérifié. Le premier périmètre proposé est un sous-lot d’écoles, collèges et lycées de l’Annuaire de l’éducation, à délimiter selon les établissements couverts par le pilote. Le filtre initial est reproductible. Chaque identifiant retenu doit encore être rapproché du référentiel canonique et approuvé avant promotion.

## Contrôles exécutés le 27 novembre 2026

- `python3 scripts/check-directory-sources.py --exports` a confirmé les décomptes des trois catalogues, les champs attendus et les métadonnées de licence. Les trois comparaisons entre sources ont chacune retourné zéro UAI commune au format attendu sur cet instantané.
- Le préparateur a été rejoué en mémoire sur des exports limités aux champs institutionnels nécessaires. Les résultats ci-dessous contiennent uniquement des agrégats. Le statut officiel `etat` a été lu séparément pour le filtrage.
- `bash scripts/test-db.sh --rest` a réussi sur PostgreSQL jetable avec des données fictives. Le test a confirmé le rejet d’un schéma incompatible, l’écriture d’un seul lot après deux relances simultanées, la quarantaine des conflits, la conservation d’une fermeture sans nom et d’un identifiant Paysage sans UAI, la restauration des lots et le cloisonnement privé du staging. La table canonique des établissements est restée vide pendant ce test.
- `npm test` a réussi avec neuf tests. Ces tests portent sur les classes et le rapprochement des parcours de la démo.

| Source | Lignes | Décompte préparé | Décision proposée |
| --- | ---: | --- | --- |
| Annuaire de l’éducation | 68 548 | 68 383 candidats, 1 doublon équivalent, 163 lignes en conflit et 1 champ invalide. Les 68 548 lignes indiquaient `OUVERT`. | 63 011 candidats ont passé le filtre initial école, collège ou lycée avec commune renseignée. Mettre en attente les 5 372 autres candidats, dont 249 sans type. Les 164 rejets restent en quarantaine. |
| Établissements fermés | 42 810 | 42 810 candidats à revoir sans nom historique exploitable dans les champs projetés. | Conserver les UAI et les périodes en préparation. Examiner une preuve officielle avant d’ajouter un nom historique ou d’établir une succession. |
| Principaux établissements du supérieur | 245 | 245 candidats et 245 identifiants Paysage distincts. Dans le contrôle des exports, 19 valeurs UAI avaient un format inattendu. | Conserver l’identité Paysage en préparation. Revoir les anciens codes, leur provenance et la distinction entre établissement et campus avant d’inclure la source. |

Les données proviennent des trois sources institutionnelles et leur réutilisation prévoit l’attribution de la source et sa date de mise à jour. Les observations peuvent évoluer entre deux instantanés. [Annuaire de l’éducation](https://data.education.gouv.fr/explore/dataset/fr-en-annuaire-education/) · [Établissements fermés](https://data.education.gouv.fr/explore/dataset/fr-en-etablissements-fermes/) · [Principaux établissements du supérieur](https://data.enseignementsup-recherche.gouv.fr/explore/dataset/fr-esr-principaux-etablissements-enseignement-superieur/) · [Licence Ouverte v2.0](https://github.com/etalab/licence-ouverte/blob/48b983e67f2dcbd9a851daa178876b1ec6b49785/LO.md)

## Critères proposés pour le sous-lot

1. Identifier le lot par sa source, sa date de publication et son empreinte SHA-256. Garder l’URL du catalogue, l’éditeur et la licence avec le manifeste d’admission. Vérifier que le total des lignes est exactement la somme des candidats, doublons équivalents et rejets. Réutiliser les mêmes octets lors du rejeu.
2. Pour chaque établissement du périmètre convenu, exiger un nom et une commune renseignés, une UAI au format attendu et un statut officiel `OUVERT` dans le même export. Appliquer la correspondance de types explicite `Ecole → primary`, `Collège → middle` et `Lycée → secondary`. Le staging conserve le statut fourni par l’export à partir de la migration 015. Préparer la projection scolaire avec `etat` et joindre la preuve d’origine au manifeste.
3. Décider du rattachement de chaque identifiant à un seul UUID canonique. Un identifiant déjà lié au même établissement réutilise l’UUID. Une nouvelle entrée reçoit un UUID dans la transaction de promotion. Une divergence avec un identifiant existant, une UAI affectée à deux entités, un renommage non corroboré ou un campus ambigu reste en attente. Une similarité de nom et de commune déclenche une revue.
4. Enregistrer dans le manifeste les comptes agrégés des candidats approuvés, mis en attente et rejetés, les motifs, le lot source et la personne chargée de la revue. Le total des candidats approuvés et en attente doit égaler le nombre de candidats du lot. Le seuil proposé est zéro conflit d’identifiant non résolu parmi les lignes admises et zéro écriture dans un parcours lors de cette opération.

## Prévisualiser un lot

Après la migration 015, le rôle d’exploitation habilité peut obtenir le résultat agrégé ci-dessous depuis `psql` sur une base jetable avec un lot fictif et son paramètre `-v batch_id=UUID`. Les rôles clients n’ont pas le droit d’appeler cette fonction.

```sql
select decision, reason, count(*)
from jadis_private.preview_directory_promotion(:'batch_id'::uuid)
group by decision, reason
order by decision, reason;
```

Utiliser l’UUID exact du manifeste et vérifier que le nombre de décisions correspond au nombre de candidats du lot. Les lignes mises en quarantaine restent dans `directory_import_rejections`. Une décision `promotable` indique que le filtre est satisfait. L’admission du lot et l’écriture canonique restent des opérations distinctes.

Projeter `identifiant_de_l_etablissement,nom_etablissement,nom_commune,type_etablissement,etat` pour une nouvelle préparation scolaire. Un lot historique sans statut reste en revue. Le rejeu des mêmes octets, avec la même source et la même date publiée, ne modifie pas le lot. Produire un nouvel export projeté pour apporter la preuve manquante, sans écraser l’empreinte du lot d’origine.

La prévisualisation vérifie les identifiants canoniques `uai` et `paysage` et signale les anciennes clés de source. Pour les écoles, l’équivalence utilise le nom, le type et le statut du référentiel. La commune n’est pas encore enregistrée dans le modèle canonique. Les homonymes dans une même commune au sein du lot et les divergences restent à revoir. Les établissements fermés ou du supérieur restent à examiner avant leur admission.

## Preuves attendues avant bascule

| Essai sur une base jetable | Résultat attendu |
| --- | --- |
| Admission d’un établissement fictif avec une UAI et un type éligibles | Un établissement et un identifiant canonique, avec un lien vérifiable au lot. |
| Rejeu du même manifeste | Aucune ligne supplémentaire et mêmes UUID. |
| Conflit d’identifiant, état incertain, type hors périmètre ou fermeture sans nom | Ligne exclue de l’admission avec un motif. Les autres décisions du lot restent traçables. |
| Interruption pendant le lot, puis reprise | Aucune publication partielle. Le rejeu rétablit les décomptes attendus. |
| Même établissement avant et après correction de libellé | UUID conservé après validation et nom précédent traité comme alias si la preuve historique le permet. Les parcours existants restent associés au même établissement. |
| Retour au lot précédent et restauration | Référentiel visible et décomptes conformes au lot précédent. Tout UUID déjà référencé par un parcours est conservé. |

Le dépôt dispose du staging et des tables canoniques privées. Le manifeste d’admission, le mécanisme de promotion et les essais de la table ci-dessus restent à réaliser. La recherche de la bêta utilise actuellement les catalogues depuis le navigateur. Pour un pilote qui utilise le référentiel canonique, vérifier une recherche côté Jadis sur un lot approuvé, sans requête sortante contenant les termes saisis, et préparer un retour à la dernière version approuvée. Le responsable données valide le sous-lot et l’opérateur valide le rejeu et le retour avant activation. [Résultats des sources et staging](directory-source-validation.md) · [Modèle canonique et contrôles](foundation-data-and-controls.md)
