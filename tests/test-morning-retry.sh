#!/usr/bin/env bash
# Teste scripts/morning-retry.sh dans un faux lab installé, SANS tmux ni launchctl réels :
# des doublons (scripts qui notent leur appel) sont placés dans $HOME/.local/bin du faux HOME,
# que le script met en tête de son PATH. Cas : .review-done récent -> sortie 0 sans relance ;
# ancien + rapport plus récent -> relance (tmux kill-session, launchctl kickstart) ; absent -> relance aussi.
# Usage : test-morning-retry.sh        Code de sortie : 0 = tout passe. Nécessite macOS (date -v, stat -f).
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v, stat -f)."; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-morning-retry.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME/.local/bin"
LAB="$TMP/racine/lab"
APPELS="$TMP/appels.log"
OK=0; KO=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
for cmd in tmux launchctl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$cmd" "$APPELS" > "$FAUXHOME/.local/bin/$cmd"
  chmod +x "$FAUXHOME/.local/bin/$cmd"
done
HOME="$FAUXHOME" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
verifier "install.sh : code 0" "$?"
mkdir -p "$LAB/data/logs" "$LAB/reports/test"
retry() { : > "$APPELS"; HOME="$FAUXHOME" bash "$LAB/scripts/morning-retry.sh" >/dev/null 2>&1; }
nb_appels() { wc -l < "$APPELS" | tr -d ' '; }
vieux() { touch -t "$(date -v-"$1"d +%Y%m%d%H%M)" "$2"; }
RAPPORT="$LAB/reports/test/round-1.md"

echo "== .review-done récent (modifié maintenant), rapport plus ancien que lui"
vieux 1 "$RAPPORT"; touch "$LAB/.review-done"
retry; CODE=$?
verifier "code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "ni tmux ni launchctl appelés" "$([ "$(nb_appels)" -eq 0 ]; echo $?)"
verifier "rien écrit dans manager.log" "$([ ! -s "$LAB/data/logs/manager.log" ]; echo $?)"

echo "== .review-done ancien (3 jours), rapport plus récent, pas de session"
vieux 3 "$LAB/.review-done"; vieux 1 "$RAPPORT"
echo "ancienne session" > "$LAB/.manager-session"
retry; CODE=$?
verifier "code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "tmux kill-session -t manager appelé" "$(grep -qx 'tmux kill-session -t manager' "$APPELS"; echo $?)"
verifier "launchctl kickstart -k gui/<uid>/com.exemple.manager appelé" \
  "$(grep -qx "launchctl kickstart -k gui/$(id -u)/com.exemple.manager" "$APPELS"; echo $?)"
verifier ".manager-session supprimé" "$([ ! -e "$LAB/.manager-session" ]; echo $?)"
verifier "manager.log mentionne la relance" "$(grep -q 'morning-retry : revue du matin absente' "$LAB/data/logs/manager.log"; echo $?)"

echo "== .review-done ancien mais aucun rapport plus récent : rien à faire"
vieux 3 "$LAB/.review-done"; vieux 4 "$RAPPORT"
retry; CODE=$?
verifier "code 0, aucun appel" "$([ "$CODE" -eq 0 ] && [ "$(nb_appels)" -eq 0 ]; echo $?)"

echo "== .review-done ancien, rapport plus récent, session active (< 15 min) : pas de relance"
vieux 3 "$LAB/.review-done"; vieux 1 "$RAPPORT"
echo "x sess1" > "$LAB/.manager-session"
TR="$FAUXHOME/.claude/projects/$(echo "$LAB" | tr '/' '-')"; mkdir -p "$TR"; touch "$TR/sess1.jsonl"
retry; CODE=$?
verifier "code 0, aucun appel, .manager-session conservé" "$([ "$CODE" -eq 0 ] && [ "$(nb_appels)" -eq 0 ] && [ -f "$LAB/.manager-session" ]; echo $?)"
verifier "manager.log : session active" "$(grep -q 'session active' "$LAB/data/logs/manager.log"; echo $?)"
rm -f "$LAB/.manager-session"

echo "== .review-done absent (revue jamais faite), un rapport existe"
rm -f "$LAB/.review-done"
retry; CODE=$?
verifier "ne plante pas (code 0)" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "relance faite (tmux + launchctl)" "$([ "$(nb_appels)" -eq 2 ]; echo $?)"

echo "== .review-done absent ET aucun rapport : rien à faire"
rm -f "$LAB/.review-done" "$LAB/.manager-session" "$LAB"/reports/*/round-*.md
TAILLE_LOG=$(wc -c < "$LAB/data/logs/manager.log")
retry; CODE=$?
verifier "code 0, aucun appel, manager.log inchangé" \
  "$([ "$CODE" -eq 0 ] && [ "$(nb_appels)" -eq 0 ] && [ "$(wc -c < "$LAB/data/logs/manager.log")" -eq "$TAILLE_LOG" ]; echo $?)"

echo "== seuil de 15 min de la session : 14 min = active (pas de relance), 16 min = inactive (relance)"
vieux 3 "$LAB/.review-done"; vieux 1 "$RAPPORT"
minutes() { touch -t "$(date -v-"$1"M +%Y%m%d%H%M)" "$2"; }
echo "x sess1" > "$LAB/.manager-session"
minutes 14 "$TR/sess1.jsonl"
retry; CODE=$?
verifier "transcript vieux de 14 min : aucun appel, .manager-session conservé" \
  "$([ "$CODE" -eq 0 ] && [ "$(nb_appels)" -eq 0 ] && [ -f "$LAB/.manager-session" ]; echo $?)"
minutes 16 "$TR/sess1.jsonl"
retry; CODE=$?
verifier "transcript vieux de 16 min : relance (tmux + launchctl), .manager-session supprimé" \
  "$([ "$CODE" -eq 0 ] && [ "$(nb_appels)" -eq 2 ] && [ ! -e "$LAB/.manager-session" ]; echo $?)"
echo "x sess-absente" > "$LAB/.manager-session"
retry
verifier "session nommée sans transcript : relance (2 appels)" "$([ "$(nb_appels)" -eq 2 ]; echo $?)"

echo "== frontière de 07:30 (jour du manageur = maintenant - 7h30) : revue à 07:30 pile = faite, 07:29 = pas faite"
JOUR=$(date -v-7H -v-30M +%F); JOURT="${JOUR//-/}"
rm -f "$LAB/.manager-session"; touch "$RAPPORT"
touch -t "${JOURT}0730" "$LAB/.review-done"
retry; CODE=$?
verifier "revue à 07:30 pile : code 0, aucun appel (même avec un rapport plus récent)" "$([ "$CODE" -eq 0 ] && [ "$(nb_appels)" -eq 0 ]; echo $?)"
touch -t "${JOURT}0729" "$LAB/.review-done"
retry; CODE=$?
verifier "revue à 07:29 : relance (2 appels)" "$([ "$CODE" -eq 0 ] && [ "$(nb_appels)" -eq 2 ]; echo $?)"
touch -t "${JOURT}0731" "$LAB/.review-done"
retry
verifier "revue à 07:31 : aucun appel" "$([ "$(nb_appels)" -eq 0 ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
