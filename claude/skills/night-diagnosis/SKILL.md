---
name: night-diagnosis
description: Utiliser quand un round est en échec, n'a pas de rapport, n'a pas tourné, ou quand l'utilisateur trouve le résultat étrange.
---

# Diagnostiquer un round

Les noms des LaunchAgents commencent par le préfixe `PREFIXE_LAUNCHAGENT` de `config.env`
(étiquettes `<préfixe>.night`, `.morning`, `.morning-retry`, `.manager`, `.now`).

1. Lis le rapport concerné (`reports/<date>/round-<id>-<projet>.md`), puis la fin du log :
   `tail -n 80 logs/<date>-round-<id>.log`
   (<id> = 1, 2 ou now-HHMM ; <date> = date de la nuit pour les rounds 1 et 2).
   Regarde aussi `logs/launchd-<job>.log` : il contient les erreurs de lancement.
2. Vérifie dans l'ordre :
   - le round avait-il des tâches ? (fichier `tasks-night.md` ou `tasks-now-*.md` du dossier du rapport,
     ou `scripts/night.sh <N> --check`, N = 1, 2 ou now)
   - le job est-il chargé ? `launchctl list | grep <préfixe>`
     Son dernier code de sortie : `launchctl print gui/$(id -u)/<préfixe>.<job>`
   - le Mac était-il éveillé et la session ouverte ? `pmset -g log | grep -i sleep | tail -20`
   - un signal oublié bloque-t-il ? `ls .night-running .now-running` (présent alors que rien ne tourne = reste d'un arrêt brutal)
   - authentification ou quota : messages de login, de limite d'usage, d'expiration dans le log
   - code 124 dans le log : temps limite atteint
   - « Operation not permitted » : fichier placé dans un dossier protégé par macOS (Bureau, Documents…)
   - commandes refusées : outil manquant dans OUTILS_EXTRA ?
   - worktree : `git -C @WORKTREES@/<projet> status` et `... stash list`
   - « a disparu de GitHub » : branche déjà mergée, il faut un nouveau nom
   - « déjà ouverte dans une autre copie » : une session directe utilise la même branche
   - échec du push ou de la PR : `gh auth status`, hook pre-push
3. Explique la cause probable en 2-3 phrases simples, sans jargon inutile.
4. Propose le correctif. S'il faut une action sur la machine (sudo, login, réglage système),
   donne la commande exacte à lancer en SSH. Ne modifie pas les scripts sans accord.
5. Si la cause est un piège qui reviendra (commande refusée, réglage manquant), propose de l'ajouter à la section
   « Pièges connus » de `memory/<projet>/<projet>-Agent-Knowledge.md`.
6. Propose de relancer (run-now) ou de replanifier pour la nuit suivante (plan-night).
