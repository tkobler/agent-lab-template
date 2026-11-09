#!/usr/bin/env bash
# Lance toute la suite de tests : bash -n sur chaque script .sh, contrôle des données personnelles
# (rouge attendu sur les fixtures, vert sur la partie publiable), tests unitaires, faux lab.
# Usage : lancer-tous-les-tests.sh [settings.json du lab réel [dossier des plist réels]]  (références facultatives,
#   lecture seule : sans elles, les comparaisons au lab réel sont ignorées et signalées « SKIP »)        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
ECHECS=0
etape() {  # <titre> <commande...>
  local titre="$1"; shift
  echo "### $titre"
  if "$@"; then echo "--> OK"; else echo "--> ECHEC (code $?)"; ECHECS=$((ECHECS + 1)); fi
  echo
}

syntaxe() {
  local f n=0 mauvais=0
  while IFS= read -r -d '' f; do
    n=$((n + 1))
    if bash -n "$f"; then echo "  ok   ${f#"$SQ"/}"; else echo "  ECHEC ${f#"$SQ"/}"; mauvais=$((mauvais + 1)); fi
  done < <(find "$SQ" -name '*.sh' -type f -print0 | sort -z)
  echo "$n script(s), $mauvais erreur(s) de syntaxe"
  [ "$mauvais" -eq 0 ]
}
rouge_sur_fixtures() {
  bash "$ICI/controle-donnees-perso.sh" "$ICI/fixtures/mauvais"; local c=$?
  echo "(code de sortie $c, un code différent de 0 est attendu)"
  [ "$c" -eq 1 ]
}

etape "bash -n sur tous les scripts" syntaxe
etape "contrôle des données personnelles : ROUGE attendu sur les fixtures" rouge_sur_fixtures
etape "contrôle des données personnelles : VERT attendu sur la partie publiable" bash "$ICI/controle-donnees-perso.sh"
etape "test du contrôle lui-même" bash "$ICI/test-controle-donnees-perso.sh"
etape "test de resolve-model.sh" bash "$ICI/test-resolve-model.sh"
etape "test de resolve-agent.sh : agents généraux et agents de projet (agents/<projet>/)" bash "$ICI/test-resolve-agent.sh"
etape "test de read-project-config.sh" bash "$ICI/test-read-project-config.sh"
etape "test de permissions-couverture.sh : une commande est-elle couverte par les permissions d'un round (glob, interdit prioritaire)" bash "$ICI/test-permissions-couverture.sh"
etape "COMMANDES_TEST : night.sh --check, vrai round, fiches, install.sh, --essai (faux lab, claude doublé)" bash "$ICI/test-commandes-test.sh"
etape "test des réglages de permissions (référence facultative : 1er argument ou REGLAGES_LAB_REFERENCE)" bash "$ICI/test-reglages.sh" "${1:-}"
etape "test des modèles de LaunchAgents (référence facultative : 2e argument ou LAUNCHAGENTS_REFERENCE)" bash "$ICI/test-launchagents.sh" "${2:-}"
etape "test de night-chain.sh : aucun plafond de rounds, relance après TIMEOUT_ROUND" bash "$ICI/test-chaine.sh"
etape "test de night.sh : reprise après TIMEOUT_ROUND (prompt, rapport)" bash "$ICI/test-reprise-timeout.sh"
tests_outils() { ( cd "$SQ" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest "$@" ); }
if [ -f "$SQ/tools/agent_knowledge.py" ]; then     # livré dans le lab publiable (généralisé) ; garde pour un dépôt sans tools/
  etape "agent_knowledge : tests unitaires du contrôle des pages Agent-Knowledge" tests_outils tools.test_agent_knowledge
  # Pages du coffre : sautées si memory/ est absent ou si la page du lab est encore le gabarit vide (3 sections, sans « ## 9. »)
  if [ -f "$SQ/memory/lab/lab-Agent-Knowledge.md" ] && grep -q '^## 9\. ' "$SQ/memory/lab/lab-Agent-Knowledge.md"; then
    etape "agent_knowledge : forme des pages Agent-Knowledge du coffre (projets déduits de memory/)" python3 "$SQ/tools/agent_knowledge.py"
  else
    echo "### agent_knowledge : forme des pages du coffre : SKIP (memory/ absent ou page encore au gabarit vide)"; echo
  fi
else
  echo "### agent_knowledge : SKIP (tools/ non livré dans ce dépôt)"; echo
fi
if [ -f "$SQ/tools/test_agents_round.py" ]; then
  etape "agents_round.py : tests unitaires (JSON de --agents)" tests_outils tools.test_agents_round
else
  echo "### agents_round : tests unitaires SKIP (tools/test_agents_round.py absent)"; echo
fi
etape "faux lab : install.sh + night.sh --check" bash "$ICI/faux-lab.sh"
etape "install.sh en place : défauts (data/projects, data/worktrees, data/logs), options, réinstallation, refus d'une cible" bash "$ICI/test-install-defaut.sh"
etape "lab dans le clone : clone + install -> git status vide, night --check, morning.sh (push memory/ seulement, main seulement), export-lab" bash "$ICI/test-lab-en-place.sh"
etape "lab dans le clone indépendant du vrai config/TASKS.md (rempli puis vide)" bash "$ICI/test-lab-en-place-isole.sh"
etape "noms anglais des signaux, archives de tâches et prompt (vrai round avec claude doublé)" bash "$ICI/test-noms-fichiers.sh"
etape "agents du lab fournis au round par --agents (JSON : généraux + projet, général gagnant, modèle résolu ; claude doublé)" bash "$ICI/test-agents-round.sh"
etape "skills du manageur : 7 skills, anciens noms absents, installation dans un faux lab, lab-Running" bash "$ICI/test-skills.sh"
etape "skills <-> garde-fous : toute écriture de skill est autorisée par settings.json" bash "$ICI/test-skills-permissions.sh"
etape "manageur : CLAUDE.md, prompts/ et agents/ (nouvelle carte, anciens chemins absents, règles conservées)" bash "$ICI/test-manageur.sh"
etape "règles strictes de CLAUDE.md = liste attendue ; décisions lab -> lab-Decisions (CLAUDE.md, skills)" bash "$ICI/test-regles-strictes.sh"
etape "ajout d'un projet : memory/<p>/ depuis les gabarits, .review-done ignoré par git (faux lab)" bash "$ICI/test-add-project.sh"
etape "morning-retry.sh : récent / ancien / absent, tmux et launchctl doublés (faux lab)" bash "$ICI/test-morning-retry.sh"
etape "memory/Home.md : tous les liens [[…]] résolus dans le faux lab installé" bash "$ICI/test-home-liens.sh"
etape "lab : export-lab.sh (liste blanche, contrôle anti-données perso bloquant, installation dans un faux lab)" bash "$ICI/test-export-lab.sh"
etape "installation à blanc comme l'ami : commandes de la partie 3 du README rejouées (export, clone, install.sh, --check, launchctl doublé)" bash "$ICI/installation-ami.sh"

if [ "$ECHECS" -eq 0 ]; then echo "TOUT PASSE"; else echo "$ECHECS étape(s) en échec"; fi
[ "$ECHECS" -eq 0 ]
