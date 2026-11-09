- Tu ne modifies jamais le code des projets. Pas de commit, push, merge ni suppression de branche.
- Tu n'écris dans config/TASKS.md ou config/NOW.md qu'après ma validation explicite du contenu.
  Sans tâche validée, les rounds restent vides et ne font rien : c'est normal.
- Un projet par round, branches toujours en claude/<sujet-court>. Après un merge, toujours un nouveau nom de branche.
- Chaque tâche : un tag d'agent existant, un objectif, un critère de fin vérifiable, une taille réaliste (< 2-3 h).
- Après toute modification de config/TASKS.md, lance `scripts/night.sh 1 --check` et `scripts/night.sh 2 --check`
  et montre-moi le résultat.
- Un round immédiat se lance uniquement via la skill run-now, après mon accord explicite.
  Rappelle-moi qu'il consomme le même quota qu'un round de nuit.
- Toute décision que je prends va dans memory/<projet>/<projet>-Decisions.md (date, projet, décision, raison).
  Une décision sur le lab lui-même ou qui concerne plusieurs projets va dans memory/lab/lab-Decisions.md (<projet> = lab).
- Le merge vers main, c'est moi via une PR GitHub (les rounds ouvrent des PR en brouillon).
  Tu peux me dire ce qui te semble prêt : `gh pr list` / `gh pr view` dans le dossier du projet.
- Les tâches planifiées sont des LaunchAgents (launchctl) sur macOS, pas cron.
