#!/usr/bin/env bash
# Teste les 7 skills du manageur (claude/skills/<nom>/SKILL.md, installées par install.sh sous <LAB>/.claude/skills/).
#   - source : 7 dossiers aux noms anglais, front matter cohérent (name = nom du dossier, description non vide) ;
#   - aucune référence à l'ancienne organisation (anciens dossiers de données, anciens noms de scripts, de signaux, de skills) ;
#   - installation dans un faux lab : skills présentes, marqueurs @…@ rendus, aucun ancien dossier de skill ;
#   - tout script « scripts/*.sh » cité par une skill existe dans le dépôt ; tout agent « agents/*.md » aussi ;
#   - chaque skill parle bien de la nouvelle organisation (chemins attendus), la revue du matin met à jour Agent-Knowledge ;
#   - memory/lab/lab-Running.md existe (remplace l'ancien fichier « en service »).
# Sécurité : HOME remplacé par un dossier vide, rien d'installé ailleurs que dans un dossier temporaire.
# Usage : test-skills.sh        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
source "$ICI/anciens-noms.sh"
SKILLS="morning-review plan-night run-now add-project direct-session create-agent night-diagnosis"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-skills.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME"
LAB="$TMP/racine/lab"
OK=0; KO=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
contient() {  # <skill> <motif fixe> : la skill source contient ce texte
  grep -qF -- "$2" "$SQ/claude/skills/$1/SKILL.md" 2>/dev/null; echo $?
}

echo "== source : claude/skills/"
verifier "claude/skills/ contient exactement 7 dossiers" "$([ -d "$SQ/claude/skills" ] && [ "$(find "$SQ/claude/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 7 ]; echo $?)"
for s in $SKILLS; do
  F="$SQ/claude/skills/$s/SKILL.md"
  verifier "$s : SKILL.md présent" "$([ -f "$F" ]; echo $?)"
  [ -f "$F" ] || continue
  verifier "$s : front matter (--- / name: $s / description: non vide / ---)" \
    "$([ "$(sed -n 1p "$F")" = '---' ] && [ "$(sed -n 2p "$F")" = "name: $s" ] && sed -n 3p "$F" | grep -Eq '^description: .{20,}' && [ "$(sed -n 4p "$F")" = '---' ]; echo $?)"
  verifier "$s : un titre de niveau 1 et des étapes numérotées" "$(grep -q '^# ' "$F" && grep -q '^1\. ' "$F"; echo $?)"
done

echo "== source : aucune référence à l'ancienne organisation"
# Motif du critère de fin, plus les anciens noms (assemblés dans anciens-noms.sh, jamais écrits en clair ici).
ANCIEN="memo""ire/|su""ivi/|${AN_FICHES}/|${AN_TASKS_UP}|${AN_NOW_UP}|nu""it\.sh"
trouve() { grep -rnE -- "$1" "$SQ/claude/skills" 2>/dev/null; }
verifier "grep des 6 anciens motifs du critère de fin (dossiers de données, fichiers de tâches, ancien script) vide" "$([ -z "$(trouve "$ANCIEN")" ]; echo $?)"
for mot in "$AN_NOW_UP" "$AN_TASKS_UP" "$AN_MODELES" "$AN_VERIFIER" "$AN_PREFIXE" "$AN_DEPOT" "$AN_PREFIXE_DEPOT" "$AN_BUILD" "$AN_PREFIXE_INTERM" "$AN_MEM_ANCIEN" \
           "$AN_NUIT_EN_COURS" "$AN_ROUND_NOW" "$AN_TACHES" "$AN_NUIT_SH" "$AN_RUNNOW_SH" "$AN_DIRECTE_SH" "$AN_MATIN_SH" \
           "$AN_REVUE_FAITE" "$AN_SK_REVUE" "$AN_SK_PLANIFIER" "$AN_SK_LANCER" "$AN_SK_AJOUTER" "$AN_SK_SESSION" "$AN_SK_CREER" "$AN_SK_DIAG" \
           "$AN_ETAT" "$AN_A_DECIDER" "$AN_EN_SERVICE" "$AN_INSTALLER_HOOKS"; do
  verifier "aucune occurrence de l'ancien nom « $mot »" "$([ -z "$(trouve "$mot")" ]; echo $?)"
done
verifier "aucun chemin de machine ni dossier personnel (dossier du lab en service, racines de comptes)" "$([ -z "$(trouve "~/c[l]aude-h[q]|/Us""ers/|/ho""me/")" ]; echo $?)"
verifier "le contrôle des données personnelles couvre claude/ et reste vert" "$(bash "$ICI/controle-donnees-perso.sh" >/dev/null 2>&1; echo $?)"

echo "== source : scripts et agents cités existent"
CITES="$(grep -rhoE 'scripts/[a-z0-9-]+\.sh' "$SQ/claude/skills" 2>/dev/null | sort -u)"
verifier "au moins un script cité (night.sh, run-now.sh, direct-session.sh…)" "$([ -n "$CITES" ]; echo $?)"
for c in $CITES; do verifier "script cité $c existe dans le dépôt" "$([ -f "$SQ/$c" ]; echo $?)"; done
for c in $(grep -rhoE 'agents/[a-z0-9-]+\.md' "$SQ/claude/skills" 2>/dev/null | sort -u); do
  verifier "agent cité $c existe dans le dépôt" "$([ -f "$SQ/$c" ]; echo $?)"
done
for c in $(grep -rhoE 'templates/[A-Za-z0-9.-]+' "$SQ/claude/skills" 2>/dev/null | sort -u); do
  verifier "gabarit cité $c existe dans le dépôt" "$([ -e "$SQ/$c" ]; echo $?)"
done

echo "== source : la nouvelle organisation est utilisée"
verifier "morning-review : repère .review-done" "$(contient morning-review '.review-done')"
verifier "morning-review : rapports dans reports/" "$(contient morning-review 'reports')"
verifier "morning-review : archives tasks-night.md / tasks-now-" "$(contient morning-review 'tasks-night.md')"
verifier "morning-review : décisions dans <projet>-Decisions, section « À trancher »" "$([ "$(contient morning-review '-Decisions')" = 0 ] && [ "$(contient morning-review 'À trancher')" = 0 ]; echo $?)"
verifier "morning-review : journal <projet>-Log" "$(contient morning-review '-Log')"
verifier "morning-review : met à jour <projet>-Agent-Knowledge (pièges)" "$([ "$(contient morning-review '-Agent-Knowledge')" = 0 ] && grep -qiE 'pièges' "$SQ/claude/skills/morning-review/SKILL.md"; echo $?)"
verifier "morning-review : section « Où en est-on » de <projet>-Project" "$([ "$(contient morning-review 'Où en est-on')" = 0 ] && [ "$(contient morning-review '-Project')" = 0 ]; echo $?)"
verifier "morning-review : remet des tâches dans config/TASKS.md et lance night.sh --check" "$([ "$(contient morning-review 'config/TASKS.md')" = 0 ] && [ "$(contient morning-review 'night.sh 1 --check')" = 0 ]; echo $?)"
verifier "morning-review : signal .night-running" "$(contient morning-review '.night-running')"
verifier "plan-night : config/TASKS.md, .night-running, night.sh 1 --check et 2 --check" \
  "$([ "$(contient plan-night 'config/TASKS.md')" = 0 ] && [ "$(contient plan-night '.night-running')" = 0 ] && [ "$(contient plan-night 'night.sh 1 --check')" = 0 ] && [ "$(contient plan-night 'night.sh 2 --check')" = 0 ]; echo $?)"
verifier "plan-night : fiches dans config/projects/ ; À trancher dans <projet>-Decisions" "$([ "$(contient plan-night 'config/projects')" = 0 ] && [ "$(contient plan-night '-Decisions')" = 0 ]; echo $?)"
verifier "run-now : config/NOW.md, section « ## NOW », .now-running, run-now.sh, night.sh now --check" \
  "$([ "$(contient run-now 'config/NOW.md')" = 0 ] && [ "$(contient run-now '## NOW')" = 0 ] && [ "$(contient run-now '.now-running')" = 0 ] && [ "$(contient run-now 'scripts/run-now.sh')" = 0 ] && [ "$(contient run-now 'night.sh now --check')" = 0 ]; echo $?)"
verifier "run-now : .night-running vérifié aussi" "$(contient run-now '.night-running')"
verifier "add-project : config/projects/<nom>.md et .env, install-hooks.sh, protection-main.json" \
  "$([ "$(contient add-project 'config/projects/')" = 0 ] && [ "$(contient add-project 'scripts/install-hooks.sh')" = 0 ] && [ "$(contient add-project 'templates/protection-main.json')" = 0 ]; echo $?)"
verifier "add-project : pages mémoire <nom>-Project et <nom>-Agent-Knowledge" "$([ "$(contient add-project '-Project')" = 0 ] && [ "$(contient add-project '-Agent-Knowledge')" = 0 ]; echo $?)"
verifier "direct-session : scripts/direct-session.sh et --close" "$([ "$(contient direct-session 'scripts/direct-session.sh')" = 0 ] && [ "$(contient direct-session '--close')" = 0 ]; echo $?)"
verifier "direct-session : suivi dans lab-Running" "$(contient direct-session 'lab-Running')"
verifier "create-agent : agents/, night.sh, prompts/night.md, Decisions" \
  "$([ "$(contient create-agent 'agents/')" = 0 ] && [ "$(contient create-agent 'prompts/night.md')" = 0 ] && [ "$(contient create-agent '-Decisions')" = 0 ]; echo $?)"
verifier "create-agent : agent général (agents/<nom>.md) ou propre à un projet (agents/<projet>/<nom>.md)" \
  "$([ "$(contient create-agent 'agents/<nom>.md')" = 0 ] && [ "$(contient create-agent 'agents/<projet>/<nom>.md')" = 0 ]; echo $?)"
verifier "create-agent : le général gagne en cas de doublon de tag" "$(contient create-agent 'général gagne')"
verifier "plan-night : agents généraux (agents/) et agents du projet (agents/<projet>/) listés" \
  "$([ "$(contient plan-night 'ls agents/')" = 0 ] && [ "$(contient plan-night 'agents/<projet>/')" = 0 ]; echo $?)"
verifier "night-diagnosis : reports/, logs/, tasks-night.md, préfixe de LaunchAgent de config.env" \
  "$([ "$(contient night-diagnosis 'reports')" = 0 ] && [ "$(contient night-diagnosis 'logs/')" = 0 ] && [ "$(contient night-diagnosis 'tasks-')" = 0 ] && [ "$(contient night-diagnosis 'PREFIXE_LAUNCHAGENT')" = 0 ]; echo $?)"
verifier "night-diagnosis : journal logs/<date>-round-<id>.log" "$(contient night-diagnosis 'round-')"

echo "== installation dans un faux lab"
SORTIE="$(HOME="$FAUXHOME" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple 2>&1)"; CODE=$?
verifier "install.sh : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
for s in $SKILLS; do
  verifier "$s : installée dans .claude/skills/$s/SKILL.md, identique à la source rendue (aucun marqueur @…@)" \
    "$([ -f "$LAB/.claude/skills/$s/SKILL.md" ] && ! grep -q '@[A-Z_]*@' "$LAB/.claude/skills/$s/SKILL.md"; echo $?)"
done
verifier ".claude/skills/ contient exactement 7 dossiers" "$([ "$(find "$LAB/.claude/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 7 ]; echo $?)"
verifier "settings.json toujours installé à côté des skills" "$([ -f "$LAB/.claude/settings.json" ]; echo $?)"
verifier "skills installées : aucune référence à l'ancienne organisation" "$([ -z "$(grep -rnE -- "$ANCIEN" "$LAB/.claude/skills" 2>/dev/null)" ]; echo $?)"
verifier "skills installées : le chemin du faux lab ou de ses clones est écrit là où la source a un marqueur" \
  "$(if grep -rq '@[A-Z_]*@' "$SQ/claude/skills"; then grep -rqF "$TMP/racine" "$LAB/.claude/skills"; else true; fi; echo $?)"
verifier "chaque skill installée cite un script qui existe dans le faux lab" \
  "$(ok=0; for c in $(grep -rhoE 'scripts/[a-z0-9-]+\.sh' "$LAB/.claude/skills" | sort -u); do [ -f "$LAB/$c" ] || ok=1; done; echo $ok)"
verifier "réinstallation : code 0 et toujours 7 skills" \
  "$(HOME="$FAUXHOME" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1; c=$?; [ "$c" -eq 0 ] && [ "$(find "$LAB/.claude/skills" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" -eq 7 ]; echo $?)"
verifier "HOME de substitution intact" "$([ -z "$(ls -A "$FAUXHOME")" ]; echo $?)"

echo "== memory/lab/lab-Running.md"
if [ ! -d "$SQ/memory" ]; then echo "  SKIP : pas de memory/ (lab publiable : le coffre n'est pas livré)"; else
R="$SQ/memory/lab/lab-Running.md"
verifier "lab-Running.md existe" "$([ -f "$R" ]; echo $?)"
verifier "lab-Running : titre, date de mise à jour, sections « En service » et « En attente »" "$(grep -q '^# ' "$R" && grep -qE '^Mis à jour : 20[0-9]{2}-[0-9]{2}-[0-9]{2}' "$R" && grep -q '^## En service' "$R" && grep -q '^## En attente' "$R"; echo $?)"
verifier "lab-Running : lien vers [[lab/lab-Project]] et [[Home]]" "$(grep -qF '[[lab/lab-Project]]' "$R" && grep -qF '[[Home]]' "$R"; echo $?)"
verifier "lab-Running : noms de scripts actuels (night-chain.sh, morning.sh)" "$(grep -q 'night-chain.sh' "$R" && grep -q 'morning.sh' "$R"; echo $?)"
verifier "lab-Running : aucun chemin de machine (racine des comptes)" "$([ -f "$R" ] && ! grep -q "/Us""ers/" "$R"; echo $?)"
verifier "lab-Running : section « Sessions directes ouvertes » (tenue par direct-session)" "$(grep -q '^## Sessions directes ouvertes' "$R"; echo $?)"
fi

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
