#!/usr/bin/env bash
# Teste que night.sh fournit lui-même au round les agents du lab par l'option --agents de claude (JSON), au lieu de
# laisser claude lire ~/.claude/agents : agents généraux (agents/*.md), puis agents du projet du round (agents/<projet>/*.md) ;
# le général gagne sur un doublon ; les agents d'un autre projet ne sont jamais fournis ; modèle résolu
# (agent > projet > lab, « inherit » = niveau suivant) ; aucun texte d'un fichier agent n'est interprété par le shell.
# Un VRAI round est lancé dans un faux lab temporaire avec un faux claude qui enregistre la valeur reçue après --agents
# (même modèle de doublure que test-noms-fichiers.sh) : aucun vrai claude, aucun push.
# Nécessite macOS (date -v dans night.sh). Usage : test-agents-round.sh     Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans night.sh)."; exit 0; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/agents-round.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME/.local/bin" "$FAUXHOME/.claude/agents"
RACINE="$TMP/racine"; LAB="$RACINE/lab"
OK=0; KO=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
dans_faux_home() { HOME="$FAUXHOME" "$@"; }
# Lit le JSON reçu par le faux claude : json_get '<expression python sur d>' -> affiche le résultat
json_get() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$TMP/agents.json" "$1" 2>&1; }

echo "== faux lab installé, faux projet git, agents du lab"
dans_faux_home bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
verifier "install.sh : code 0" "$?"
printf '\nPUSH_BRANCHES="non"\nOUVRIR_PR="non"\n' >> "$LAB/config.env"
git init -q --bare -b main "$RACINE/origine.git"
git clone -q "$RACINE/origine.git" "$RACINE/projets/demo" 2>/dev/null
git -C "$RACINE/projets/demo" -c user.name=Essai -c user.email=essai@exemple.com commit -q --allow-empty -m init
git -C "$RACINE/projets/demo" push -q origin main 2>/dev/null
mkdir -p "$LAB/agents/demo" "$LAB/agents/autre"
# agent de projet en doublon d'un général : le général doit gagner
printf '%s\n' '---' 'name: codeur' 'description: Version du projet' 'model: haiku' '---' 'PROMPT-PROJET-DOUBLON' > "$LAB/agents/demo/codeur.md"
# agent propre au projet, avec un modèle explicite, et du texte qui ressemble à du shell
printf '%s\n' '---' 'name: analyste' 'description: Analyse "les" données' 'tools: Read, Grep' 'model: sonnet' '---' \
  'Analyse $(touch '"$TMP"'/INJECTE) `touch '"$TMP"'/INJECTE2` "quoi"' > "$LAB/agents/demo/analyste.md"
# agent d'un autre projet : jamais fourni
printf '%s\n' '---' 'name: espion' 'description: Autre projet' '---' 'Jamais' > "$LAB/agents/autre/espion.md"
# agent hérité de ~/.claude/agents : ne doit pas être fourni par night.sh
printf '%s\n' '---' 'name: ancien' 'description: Ancien lab' '---' 'Ancien' > "$FAUXHOME/.claude/agents/ancien.md"
git -C "$LAB" add -A
git -C "$LAB" -c user.name=Essai -c user.email=essai@exemple.com commit -q -m "agents de test"

printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/caffeinate"
printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/gtimeout"
printf '%s\n' '#!/bin/bash' \
  'n=0; for a in "$@"; do [ "$a" = --agents ] && n=$((n + 1)); done; echo "$n" > "$SORTIES_ESSAI/nb-agents.txt"' \
  'while [ $# -gt 0 ]; do [ "$1" = --agents ] && printf %s "$2" > "$SORTIES_ESSAI/agents.json"; shift; done' \
  'exit 0' > "$FAUXHOME/.local/bin/claude"
chmod +x "$FAUXHOME/.local/bin/"*
export SORTIES_ESSAI="$TMP"

tache() { printf '## ROUND 1\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Tâche\n- [analyste] Autre tâche\n' > "$LAB/config/TASKS.md"; }
lancer() {  # relance un round de nuit
  rm -f "$TMP/agents.json" "$TMP/nb-agents.txt" "$LAB/.night-running"
  tache
  dans_faux_home bash "$LAB/scripts/night.sh" 1 > "$TMP/sortie.txt" 2>&1; CODE=$?
}

echo "== modèle du projet : opus"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\nMODELE="opus"\n' "$RACINE/projets/demo" > "$LAB/config/projects/demo.env"
lancer
verifier "night.sh 1 : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "claude reçoit --agents une seule fois" "$([ "$(cat "$TMP/nb-agents.txt" 2>/dev/null)" = 1 ]; echo $?)"
[ -s "$TMP/agents.json" ] || { echo "    | sortie de night.sh :"; head -30 "$TMP/sortie.txt" | sed 's/^/    | /'; }
verifier "la valeur est un JSON valide" "$(python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/agents.json" 2>/dev/null; echo $?)"
verifier "agents fournis : généraux + agents du projet, sans l'autre projet ni ~/.claude/agents" \
  "$([ "$(json_get 'sorted(d)')" = "['analyste', 'chercheur', 'codeur', 'relecteur', 'testeur']" ]; echo $?)"
verifier "doublon : le général gagne (prompt et description du général)" \
  "$([ "$(json_get '"PROMPT-PROJET-DOUBLON" not in d["codeur"]["prompt"] and d["codeur"]["prompt"].startswith("Tu es un")')" = True ]; echo $?)"
verifier "général en « inherit » : modèle du projet (opus)" "$([ "$(json_get 'd["codeur"].get("model")')" = opus ]; echo $?)"
verifier "agent de projet avec model: sonnet : sonnet l'emporte" "$([ "$(json_get 'd["analyste"].get("model")')" = sonnet ]; echo $?)"
verifier "agent de projet : description, outils (liste) et prompt" \
  "$([ "$(json_get 'd["analyste"]["description"], d["analyste"]["tools"], d["analyste"]["prompt"][:7]')" = "('Analyse \"les\" données', ['Read', 'Grep'], 'Analyse')" ]; echo $?)"
verifier "le texte des fichiers agents n'est pas interprété par le shell (aucun fichier INJECTE)" "$([ ! -e "$TMP/INJECTE" ] && [ ! -e "$TMP/INJECTE2" ]; echo $?)"
verifier "le prompt de l'agent de projet garde le texte tel quel" \
  "$([ "$(json_get 'd["analyste"]["prompt"].count("touch") == 2 and "(touch" in d["analyste"]["prompt"]')" = True ]; echo $?)"

echo "== sans modèle de projet : modèle du lab (config.env)"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$RACINE/projets/demo" > "$LAB/config/projects/demo.env"
printf '\nMODELE_LAB="sonnet"\n' >> "$LAB/config.env"
lancer
verifier "night.sh 1 : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "général en « inherit » : modèle du lab (sonnet)" "$([ "$(json_get 'd["testeur"].get("model")')" = sonnet ]; echo $?)"

echo "== sans aucun réglage de modèle : pas de champ model pour un agent « inherit »"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$RACINE/projets/demo" > "$LAB/config/projects/demo.env"
printf '\nMODELE_LAB=""\nANTHROPIC_MODEL=""\n' >> "$LAB/config.env"
lancer
verifier "night.sh 1 : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "pas de champ model sur un général « inherit »" "$([ "$(json_get '"model" in d["codeur"]')" = False ]; echo $?)"
verifier "l'agent de projet garde son model: sonnet" "$([ "$(json_get 'd["analyste"].get("model")')" = sonnet ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
