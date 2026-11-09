#!/usr/bin/env bash
# Teste scripts/resolve-agent.sh : un tag d'agent est cherché dans agents/<tag>.md (agents généraux) puis dans
# agents/<projet>/<tag>.md (agents du projet du round seulement). Le général gagne en cas de doublon (avertissement
# sur la sortie d'erreur). Un sous-dossier d'un autre projet n'est jamais lu.
# Usage : test-resolve-agent.sh        Code de sortie : 0 = tous les tests passent.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
SCRIPT="$SQ/scripts/resolve-agent.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-agent.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0
egal() {  # <nom> <attendu> <obtenu>
  if [ "$2" = "$3" ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1 : attendu « $2 », obtenu « $3 »"; fi
}
A="$TMP/agents"
mkdir -p "$A/demo" "$A/autre"
echo general > "$A/codeur.md"
echo general > "$A/relecteur.md"
echo projet  > "$A/demo/dev-demo.md"
echo projet  > "$A/demo/codeur.md"          # doublon avec le général
echo autre   > "$A/autre/dev-autre.md"      # agent d'un autre projet
echo autre   > "$A/autre/relecteur.md"      # doublon, mais d'un autre projet
chemin() { bash "$SCRIPT" "$A" "$@" 2>/dev/null; }      # <projet> <tag> : chemin trouvé, rien sinon

echo "== agent général"
egal "général trouvé" "$A/relecteur.md" "$(chemin demo relecteur)"
egal "général trouvé sans projet" "$A/relecteur.md" "$(chemin '' relecteur)"

echo "== agent du projet"
egal "agent du projet trouvé dans agents/<projet>/" "$A/demo/dev-demo.md" "$(chemin demo dev-demo)"

echo "== doublon général / projet : le général gagne, avec un avertissement"
egal "le général gagne" "$A/codeur.md" "$(chemin demo codeur)"
AVERT="$(bash "$SCRIPT" "$A" demo codeur 2>&1 >/dev/null)"
egal "avertissement sur la sortie d'erreur" "0" "$(grep -q 'ATTENTION' <<<"$AVERT" && grep -q 'agents/demo/codeur.md' <<<"$AVERT"; echo $?)"
AVERT="$(bash "$SCRIPT" "$A" demo dev-demo 2>&1 >/dev/null)"
egal "pas d'avertissement sans doublon" "" "$AVERT"
AVERT="$(bash "$SCRIPT" "$A" demo relecteur 2>&1 >/dev/null)"
egal "doublon dans le dossier d'un AUTRE projet : pas d'avertissement" "" "$AVERT"

echo "== tag absent, sous-dossier d'un autre projet"
bash "$SCRIPT" "$A" demo inconnu >/dev/null 2>&1; egal "tag absent : code 1" "1" "$?"
egal "tag absent : rien d'affiché" "" "$(chemin demo inconnu)"
bash "$SCRIPT" "$A" demo dev-autre >/dev/null 2>&1; egal "agent d'un autre projet : code 1" "1" "$?"
bash "$SCRIPT" "$A" '' dev-demo >/dev/null 2>&1; egal "sans projet, un agent de projet n'est pas trouvé : code 1" "1" "$?"
bash "$SCRIPT" "$A" autre dev-demo >/dev/null 2>&1; egal "agent du projet demo demandé pour le projet autre : code 1" "1" "$?"

echo "== valeurs hostiles"
bash "$SCRIPT" "$A" demo ../codeur >/dev/null 2>&1; egal "tag avec .. refusé : code 1" "1" "$?"
bash "$SCRIPT" "$A" demo autre/dev-autre >/dev/null 2>&1; egal "tag avec / refusé : code 1" "1" "$?"
bash "$SCRIPT" "$A" ../autre dev-autre >/dev/null 2>&1; egal "projet avec .. refusé : code 1" "1" "$?"
bash "$SCRIPT" "$A" autre/x dev-autre >/dev/null 2>&1; egal "projet avec / refusé : code 1" "1" "$?"
bash "$SCRIPT" "$A" demo '' >/dev/null 2>&1; egal "tag vide : code 1" "1" "$?"
mkdir -p "$A/demo/dossier.md"
bash "$SCRIPT" "$A" demo dossier >/dev/null 2>&1; egal "un dossier nommé <tag>.md n'est pas un agent : code 1" "1" "$?"
bash "$SCRIPT" "$TMP/nexiste-pas" demo codeur >/dev/null 2>&1; egal "dossier d'agents absent : code 1" "1" "$?"

echo "== mauvais usage"
bash "$SCRIPT" >/dev/null 2>&1; egal "sans argument : code 2" "2" "$?"
bash "$SCRIPT" "$A" demo >/dev/null 2>&1; egal "deux arguments : code 2" "2" "$?"

echo "== utilisation comme bibliothèque (source)"
egal "trouver_agent après source" "$A/demo/dev-demo.md" "$(bash -c 'source "$1"; trouver_agent "$2" demo dev-demo' _ "$SCRIPT" "$A" 2>/dev/null)"

echo "== agents réels du dépôt"
# Découverte générique (aucun nom en dur) : premier agents/<projet>/<agent>.md du dépôt, s'il y en a
PROJ_REEL=""; AGENT_REEL=""
for d in "$SQ"/agents/*/; do
  [ -d "$d" ] || continue
  for f in "$d"*.md; do
    [ -f "$f" ] || continue
    PROJ_REEL="$(basename "$d")"; AGENT_REEL="$(basename "$f" .md)"; break 2
  done
done
if [ -n "$PROJ_REEL" ]; then
  egal "agent réel trouvé pour son projet" "$SQ/agents/$PROJ_REEL/$AGENT_REEL.md" "$(bash "$SCRIPT" "$SQ/agents" "$PROJ_REEL" "$AGENT_REEL" 2>/dev/null)"
  bash "$SCRIPT" "$SQ/agents" lab "$AGENT_REEL" >/dev/null 2>&1; egal "agent réel introuvable pour le projet lab : code 1" "1" "$?"
  bash "$SCRIPT" "$SQ/agents" '' "$AGENT_REEL" >/dev/null 2>&1; egal "agent réel introuvable sans projet : code 1" "1" "$?"
else
  echo "  SKIP agents de projet absents de ce dépôt (lab publiable)"
fi
egal "codeur (général réel) trouvé pour un projet quelconque" "$SQ/agents/codeur.md" "$(bash "$SCRIPT" "$SQ/agents" un-projet-quelconque codeur 2>/dev/null)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
