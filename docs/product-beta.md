# Jadis — parcours de la bêta sur invitation

La démo de constellation et la bêta partagent la palette Internet 1999. La démo utilise uniquement des personnes fictives. Le parcours ci-dessous est vérifié en développement et la mise en service exige les décisions du [dossier pilote](pilot-readiness.md).

## Du compte aux retrouvailles

1. Confirmer son email et activer une invitation à usage unique. Le profil utilise un nom affiché ou un pseudonyme. Les emails restent dans Auth.
2. Ajouter à la frise un lieu, une commune et des années civiles inclusives. Les étapes sont privées par défaut. Le parcours scolaire historique reste accessible dans la bêta.
3. Activer la découverte sur le profil et sur une étape. Une recherche trouve les personnes volontaires qui ont déclaré le même type de lieu, le même nom et la même commune sur une période en commun. L’année du souvenir affine ces croisements. La casse et les espaces n’affectent pas la comparaison. Le résultat est une déclaration, pas une preuve d’identité.
4. Enregistrer une recherche pour la relancer. La recherche et ses critères restent visibles uniquement par son titulaire. Retirer l’étape efface les recherches qui s’y rapportent.
5. Envoyer puis accepter une demande avant d’ouvrir une conversation. Les blocages s’appliquent dans les deux sens à la découverte, aux reconnexions et aux lectures des capsules.

## Capsules et albums

Le créateur choisit une année dans une étape qu’il a activée. Il peut inviter des contacts déjà reconnectés qui ont déclaré le même lieu et la même année. L’invitation doit être acceptée avant la lecture et la contribution. Le créateur peut supprimer sa capsule. Quitter une capsule supprime ses propres contributions.

Un souvenir peut contenir une légende et une photo de 192 pixels de côté au maximum. Le navigateur rééchantillonne la photo et transmet uniquement les valeurs RGB. La base valide les dimensions et la longueur des pixels, et l’original et ses métadonnées ne sont pas stockés. Les albums restent accessibles via l’API de la capsule aux seuls membres autorisés. La présente bêta ne propose aucun lien public de partage.

## Commandes de compte

La réinitialisation de mot de passe utilise l’email Auth et un retour vers la page bêta. L’export JSON fournit les données de compte, de profil, de parcours, les recherches et le texte des contributions du titulaire. Les images et les conversations ne font pas partie de ce fichier. La procédure réglementaire d’accès et de portabilité reste à valider avant pilote.

La suppression demande une confirmation explicite et une authentification récente par mot de passe. Elle supprime le compte Auth et les lignes liées selon les règles de cascade. Une capsule possédée et les contributions qu’elle contient sont supprimées avec son créateur. La conservation des signalements, journaux et sauvegardes relève des décisions avant pilote.

## Vérification et retour

- `npm test` vérifie le matching et les classes de la démo.
- `bash scripts/test-db.sh --auth` rejoue les migrations sur PostgreSQL jetable. Les tests utilisent aussi PostgREST, Supabase Auth et un récepteur SMTP isolé. Ils contrôlent les permissions de la frise et des recherches, le consentement à l’invitation, la visibilité des textes et photos, le blocage, l’export et la suppression du compte.
- Le lot utilise des migrations additives. En développement, retirer les pages et modules de bêta exposés permet de suspendre ces parcours. Une fois des données écrites, conserver une sauvegarde et valider le retour avec l’opérateur avant de retirer les tables ou révoquer des accès.

L’activation du pilote demande encore le contrôle du SMTP et des redirections de l’instance hébergée, l’examen des candidats de l’annuaire, un exercice de restauration et la validation des responsabilités d’exploitation et de traitement des données.
