---
name: run-now
description: Utiliser quand l'utilisateur veut qu'un travail d'agent soit fait tout de suite, sans attendre la nuit (« lance maintenant », « fais-le tout de suite », « lance le round »).
---

# Lancer un round tout de suite

1. Vérifie que la machine est libre : `ls .now-running .night-running`. Si l'un existe, explique
   ce qui tourne et propose d'attendre ou de planifier pour la nuit (skill plan-night).
2. Construis le round comme dans plan-night : un projet, une branche claude/*, 1 à 3 tâches
   avec tag d'agent, objectif et critère de fin. Vise moins de 2 h de travail.
3. Rappelle en une ligne que ce round consomme le même quota qu'un round de nuit.
4. Montre le `config/NOW.md` proposé et demande une validation explicite.
5. Après accord : écris `config/NOW.md` (section « ## NOW »), puis lance `scripts/night.sh now --check`
   et montre le résultat.
6. Lance `scripts/run-now.sh` **en arrière-plan** (run_in_background) et dis à l'utilisateur
   que tu le préviendras à la fin. Tu peux continuer à discuter pendant ce temps.
7. Quand la commande se termine : lis le rapport (`reports/<date>/round-now-HHMM-<projet>.md`) et résume en 3 lignes
   (statut, ce qui est fait, PR). Si ce round vient de `config/TASKS.md` : vide-le de `config/TASKS.md` SEULEMENT
   s'il est fini ✅ (puis `scripts/night.sh 1 --check` et `scripts/night.sh 2 --check`).
   Coupé, en échec ou partiel : il RESTE dans `config/TASKS.md` (réduit à ce qui reste) pour que la nuit le reprenne.
   Ensuite, comme la skill morning-review (étapes 4 et 5), dans cet ORDRE : d'abord les écritures (sections du haut de
   `memory/<projet>/<projet>-Decisions.md`, journal `<projet>-Log`, pièges dans `<projet>-Agent-Knowledge`,
   « Où en est-on » de `<projet>-Project`, `touch .review-done`), ensuite le message de revue (résumé en 3 lignes +
   liste D1/R1…). Ce message complet est TOUJOURS le DERNIER du tour : jamais suivi d'appels d'outils, jamais remplacé
   par le fichier du rapport.
8. Si le lancement échoue (machine occupée, job absent) : explique simplement et propose la nuit.
