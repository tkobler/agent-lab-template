---
name: plan-night
description: Utiliser quand l'utilisateur veut définir, modifier, annuler ou valider les tâches de la prochaine nuit, ou dit par exemple « cette nuit il faudrait… ».
---

# Planifier la nuit

1. Si `.night-running` existe : une nuit tourne. On peut discuter mais on n'écrit pas `config/TASKS.md`
   avant que `scripts/morning.sh` l'ait remis à zéro. Garde le brouillon dans la section « Où en est-on »
   de `memory/<projet>/<projet>-Project.md` du projet concerné.
2. Rassemble le contexte : la section « Où en est-on » de chaque `memory/<projet>/<projet>-Project.md` et
   `memory/lab/lab-Agent-Knowledge.md`, les entrées « À reprogrammer » en haut de `memory/<projet>/<projet>-Decisions.md`
   (à proposer en premier), les derniers rapports de `reports/` (tâches inachevées, propositions),
   les décisions déjà prises (même page), la liste des agents généraux (`ls agents/`), ceux du projet concerné (`ls agents/<projet>/`) et la liste des projets (`ls config/projects/`).
3. Pour chaque tâche envisagée, construis avec l'utilisateur :
   - le tag d'agent (doit exister dans `agents/` ou dans `agents/<projet>/` du projet de la tâche ; l'agent d'un
     autre projet est introuvable ; `night.sh <N> --check` le confirme, et le général gagne si un tag est en double),
   - l'objectif en une phrase,
   - le critère de fin vérifiable (tests verts, note écrite, endpoint qui répond...),
   - le hors-périmètre si utile,
   - une estimation : si c'est trop gros pour un round, propose de découper.
4. Répartition : un projet par round, 1 à 4 tâches par round, les plus importantes d'abord.
   Branche : reprendre la branche claude/* existante pour continuer un travail NON mergé,
   sinon claude/<sujet-court>. Si une session directe est ouverte sur la même branche, préviens :
   la nuit ne pourra pas l'utiliser.
5. Montre le `config/TASKS.md` complet proposé et demande une validation explicite (« je valide ? »).
6. Après accord seulement : écris `config/TASKS.md` en gardant le bloc de règles en commentaire,
   puis lance `scripts/night.sh 1 --check` et `scripts/night.sh 2 --check` et montre le résultat.
7. Si l'utilisateur ne veut rien cette nuit : laisse les deux rounds vides et confirme que la nuit ne fera rien.
8. Mets à jour la section « Où en est-on » du projet et retire de « À reprogrammer » (`<projet>-Decisions`) les tâches
   remises dans `config/TASKS.md`. Note dans `<projet>-Decisions` la décision de lancer ces tâches (date, projet, décision, raison) ;
   si la décision concerne le lab ou plusieurs projets, note-la dans `memory/lab/lab-Decisions.md` (`<projet>` = lab).
