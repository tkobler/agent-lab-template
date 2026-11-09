#!/usr/bin/env bash
# Teste la section « Règles strictes » de CLAUDE.md : elle doit être identique, ligne à ligne, à la liste attendue
# (tests/fixtures/regles-strictes.attendu.md). Une règle retirée, ajoutée ou modifiée fait échouer le test ;
# si le changement est voulu, mettre la liste attendue à jour dans le même commit.
# Vérifie aussi que les décisions du lab / multi-projets sont dirigées vers memory/lab/lab-Decisions.md
# (CLAUDE.md et skills morning-review, plan-night).
# Usage : test-regles-strictes.sh [CLAUDE.md à tester]     (défaut : CLAUDE.md du dépôt)     Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
CLAUDE="${1:-$SQ/CLAUDE.md}"
ATTENDU="$ICI/fixtures/regles-strictes.attendu.md"
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
section() { awk '/^## Règles strictes/{f=1;next} /^## /{f=0} f' "$1" 2>/dev/null; }
puces() { grep -c '^- ' <<<"$1"; }

echo "== CLAUDE.md : section « Règles strictes » = liste attendue"
verifier "CLAUDE.md lisible" "$([ -f "$CLAUDE" ]; echo $?)"
verifier "liste attendue présente et non vide" "$([ -s "$ATTENDU" ]; echo $?)"
REEL="$(section "$CLAUDE")"
ATT="$(cat "$ATTENDU" 2>/dev/null)"
verifier "la section « Règles strictes » existe" "$([ -n "$REEL" ]; echo $?)"
DIFF="$(diff <(printf '%s\n' "$REEL") <(printf '%s\n' "$ATT"))"; rc=$?
verifier "section identique à la liste attendue" "$rc"
[ -n "$DIFF" ] && printf '%s\n' "$DIFF" | sed 's/^/       /'
verifier "même nombre de règles ($(puces "$ATT"))" "$([ "$(puces "$REEL")" = "$(puces "$ATT")" ]; echo $?)"

echo "== décisions du lab / multi-projets : memory/lab/lab-Decisions.md"
verifier "règle des décisions : memory/lab/lab-Decisions.md et <projet> = lab ensemble" \
  "$(grep -F 'memory/lab/lab-Decisions.md' <<<"$REEL" | grep -qF '<projet> = lab'; echo $?)"
CARTE="$(awk '/^## Carte des fichiers/{f=1;next} /^## /{f=0} f' "$CLAUDE" 2>/dev/null)"
verifier "carte des fichiers : ligne lab-Decisions = décisions lab / multi-projets" \
  "$(grep -F 'lab-Decisions' <<<"$CARTE" | grep -qF 'multi-projets'; echo $?)"
for s in morning-review plan-night; do
  verifier "skill $s : cite memory/lab/lab-Decisions.md" "$(grep -qF 'memory/lab/lab-Decisions.md' "$SQ/claude/skills/$s/SKILL.md"; echo $?)"
done

# Cas négatif permanent (seulement au niveau racine) : une copie de CLAUDE.md sans une règle doit faire échouer le test.
if [ $# -eq 0 ]; then
  echo "== cas négatif : copie de CLAUDE.md sans une règle -> code non nul"
  TMP="$(mktemp -d)"
  grep -v '^- Les tâches planifiées sont des LaunchAgents' "$CLAUDE" >"$TMP/CLAUDE.md"
  verifier "la copie diffère bien de l'original" "$(cmp -s "$CLAUDE" "$TMP/CLAUDE.md"; [ $? -ne 0 ]; echo $?)"
  bash "${BASH_SOURCE[0]}" "$TMP/CLAUDE.md" >"$TMP/sortie.txt" 2>&1; rc=$?
  verifier "règle retirée : le test sort avec un code non nul (code $rc)" "$([ "$rc" -ne 0 ]; echo $?)"
  verifier "règle retirée : l'échec est signalé (ECHEC)" "$(grep -q 'ECHEC' "$TMP/sortie.txt"; echo $?)"
  rm -rf "$TMP"
fi

echo; echo "$OK ok, $KO échec(s)"
[ "$KO" -eq 0 ]
