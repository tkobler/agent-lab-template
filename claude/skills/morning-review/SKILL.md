---
name: morning-review
description: Utiliser quand de nouveaux rapports sont disponibles, ou quand l'utilisateur demande ce qui a été fait, le bilan, le rapport du jour. Présente les résultats, recueille son avis et met la mémoire à jour.
---

# Revue des rapports

Où vit quoi (voir la carte des fichiers de CLAUDE.md) : les rapports sont dans `reports/`, la mémoire dans
`memory/<projet>/` (pages `<projet>-Decisions`, `<projet>-Log`, `<projet>-Project`, `<projet>-Agent-Knowledge` ;
`<projet>` peut être `lab` : décisions du lab ou multi-projets),
l'état de la machine dans `memory/lab/lab-Running.md`. Le repère « revue faite » est le fichier caché `.review-done`
à la racine du lab.

1. Nouveaux rapports : `find reports -name 'round-*.md' -newer .review-done`
   (si le repère n'existe pas : tous les rapports).
2. Pour chaque rapport :
   - lis-le en entier, ainsi que le fichier de tâches du même dossier (`tasks-night.md` ou `tasks-now-*.md`) ;
   - vérifie la réalité dans le worktree :
     `git -C @WORKTREES@/<projet> log --oneline origin/<BRANCHE_BASE>..HEAD`
     `git -C @WORKTREES@/<projet> diff --stat origin/<BRANCHE_BASE>...HEAD`
   - si le rapport annonce des choses absentes des commits, signale l'écart ;
   - regarde la PR : `cd @PROJETS@/<projet> && gh pr list --head <branche>`.
3. Commence par le RÉSUMÉ DE LA NUIT, avant toute décision. Par round :
   - titre : `### Round N — <projet> — ✅ / ⚠️ / ❌` avec la branche et la PR (numéro, brouillon, branche cible) ;
   - **Fait :** ce qui a été produit, en langage clair (2-4 puces, pas de jargon inutile) ;
   - **Réussi / vérifié :** ce que tu as contrôlé toi-même (commits présents, fichiers touchés, zones
     interdites intactes, PR) ;
   - **Problèmes / échecs :** tâches ratées ou partielles, commandes refusées et leurs conséquences,
     écarts entre rapport et commits, prérequis manquants. Si rien : « Aucun ».
   Un petit tableau (tâche | statut | résultat) est bienvenu s'il rend le tout plus lisible.
   Un round sans tâche : une ligne. Aucun nouveau rapport : dis-le en une ligne et arrête-toi là.
   Puis la section **À reprogrammer** : toutes les tâches non terminées de la nuit. Compare le fichier de
   tâches du round (`tasks-night.md`…) avec le rapport : toute tâche absente du rapport ou pas ✅ compte,
   même si le round a été coupé avant de remplir la section « Tâches non terminées ».
   - numérote T1, T2… ; pour chacune : titre, projet, raison (temps, blocage…), ce qui reste,
     et le texte qui serait remis dans `config/TASKS.md` (celui du rapport, sinon le texte d'origine réduit à ce qui reste) ;
   - termine par : « Réponds par ex. : T1 T2 (ou T tout) pour les remettre la nuit prochaine. »
   - si tout est terminé : « Rien à reprogrammer. »
4. Puis LES DÉCISIONS :
   - rassemble la section « Décisions » de chaque nouveau rapport, plus les entrées encore ouvertes
     (sections « À trancher », « Choix faits seul à valider » et « À reprogrammer » en haut de chaque
     `memory/<projet>/<projet>-Decisions.md`, y compris `memory/lab/lab-Decisions.md` pour le lab) ;
   - numérote : D1, D2… pour « À trancher », R1, R2… pour « Choix faits seul » ;
   - regroupe par thème (ex. GPS, pause, agents et permissions, dépôt) avec un titre par thème ;
     si c'est long, découpe en plusieurs messages (un par thème) pour rester lisible sur téléphone ;
   - chaque « À trancher » est un bloc, toujours avec la même structure :
     `**D1 — <question en clair>**`
     *Contexte :* de quoi il s'agit et pourquoi la question se pose (1-2 phrases, sans renvoyer au rapport).
     *A) … :* ce que ça implique concrètement (avantage / inconvénient). Idem pour B), C)…
       (un tableau option | effet | inconvénient est possible quand il y a 3 options ou plus)
     *Reco : X.* La raison en une phrase.
     *Sans réponse :* ce qui s'applique en attendant.
   - chaque « Choix fait seul » : `**R1 — <choix en clair>**` puis une phrase sur le pourquoi et
     *Pour annuler :* … Plusieurs R courts peuvent tenir dans un tableau (choix | pourquoi | pour annuler).
   - ajoute en fin de liste : « Réponds par ex. : D1 A, D2 reco, R1 ok, R2 annule. Ce que tu ne tranches pas
     reste en attente pour demain. »
   - s'il n'y a aucune décision : dis-le en une ligne.
   Le message se termine par : « Par quoi on commence : décisions, détails d'un round, ou prochaines tâches ? »
   ORDRE OBLIGATOIRE : AVANT d'envoyer ce message de revue, écris dans la mémoire (rien ne doit se perdre si la session
   est remplacée), puis envoie la revue. La revue complète (résumé + décisions + À reprogrammer) est TOUJOURS le DERNIER
   message du tour : jamais suivie d'appels d'outils, jamais remplacée par le simple chemin ou le contenu du fichier du
   rapport. Prépare donc le texte, fais les écritures, puis envoie le texte en dernier. Écritures à faire d'abord :
   - dans la page `memory/<projet>/<projet>-Decisions.md` de chaque projet concerné (`lab` compris), tiens à jour les sections du
     haut avec toutes les entrées de la liste, sans doublon : « À trancher » (D), « Choix faits seul à valider » (R)
     et « À reprogrammer » (T : `date — projet — T1 titre — branche — texte prêt à copier — rapport`) ;
   - complète le journal `memory/<projet>/<projet>-Log.md` de chaque projet (le plus récent en haut ; crée la page sur le
     modèle des autres si elle n'existe pas) : un bloc `## date — nuit, round N (ou round immédiat HHhMM) — branche — PR #x`
     puis une ligne par tâche, quel que soit le statut : `- ✅/⚠️/❌ [agent] titre — résultat en quelques mots — commits`,
     avec le lien vers le rapport ;
   - mets à jour la section « Pièges connus » (section 6) de `memory/<projet>/<projet>-Agent-Knowledge.md` à partir de la
     section « Pièges / à savoir » des rapports : commandes refusées et leur alternative, bugs et fausses pistes, outils
     manquants. Ajoute seulement ce qui est nouveau, retire ce qui est devenu faux, garde la page sous 150 lignes et
     refais la date de la section 9 ; si le rapport n'a rien de nouveau, ne touche pas à la page ;
   - puis `touch .review-done` à la racine du lab (toujours avant le message de revue).
5. Quand l'utilisateur répond (même partiellement) :
   - chaque décision prise va dans la section « Décisions prises » de `<projet>-Decisions` (date, décision, raison, sous le
     bon thème) et sort des sections du haut ; une décision sur le lab lui-même ou qui concerne plusieurs projets va dans
     `memory/lab/lab-Decisions.md` (`<projet>` = lab) ;
   - ce qui demande du travail (changer d'option, annuler un choix) devient une proposition de tâche ;
   - « T1 T2 » ou « T tout » : sa réponse vaut validation de ces tâches telles qu'affichées. Ajoute-les en tête
     du round de leur projet dans `config/TASKS.md` (règles de plan-night : même branche, un projet par round,
     durée du round), lance `scripts/night.sh 1 --check` et `scripts/night.sh 2 --check`, montre le résultat,
     note-le dans `<projet>-Decisions` et retire ces T de « À reprogrammer ». Si ça ne rentre pas (autre projet déjà sur
     les deux rounds, durée) : dis-le et propose un arbitrage avant d'écrire. Si `.night-running` existe : garde-les pour
     après `scripts/morning.sh` ;
   - les sections du haut de `<projet>-Decisions` ne gardent QUE les entrées non tranchées (date, projet, texte, rapport d'origine).
   Détaille une entrée seulement si l'utilisateur le demande.
6. Demande son avis sur la qualité du travail. Si un retour concerne une manière de travailler,
   propose de l'ajouter dans la fiche projet `config/projects/<projet>.md` (section « Notes du manageur »),
   avec son accord, et dans les conventions de `<projet>-Agent-Knowledge`.
7. Mets à jour la section « Où en est-on » (dans le tour de la revue : avant le message de revue, comme à l'étape 4) de `memory/<projet>/<projet>-Project.md` (travail en cours, PR ouvertes)
   et, pour le lab, `memory/lab/lab-Agent-Knowledge.md` (section 1, « État ») ainsi que `memory/lab/lab-Running.md` si
   quelque chose a changé sur la machine (correctif appliqué, réglage, merge fait par l'utilisateur).
8. Propose d'enchaîner avec plan-night, en reprenant les tâches inachevées, les décisions prises
   et les propositions des agents.
