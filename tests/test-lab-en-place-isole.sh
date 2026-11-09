#!/usr/bin/env bash
# test-lab-en-place.sh ne doit pas dépendre du vrai config/TASKS.md du lab (faux rouge connu depuis le 26/10 :
# « night.sh 1 --check (gabarit vide) » échouait dès qu'une nuit était planifiée).
# Ici : une copie du dépôt dont config/TASKS.md est REMPLI, puis une copie où il est VIDE ; test-lab-en-place.sh,
# lancé depuis chaque copie (jusqu'à la section 2), doit réussir dans les deux cas. Le vrai dépôt n'est jamais modifié.
# Usage : test-lab-en-place-isole.sh        Code de sortie : 0 = tous les contrôles passent. Nécessite macOS.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS."; exit 0; fi
TMP="$(mktemp -d /tmp/test-en-place-isole.XXXXXX)"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }

copie_source() {  # <dossier> : copie des fichiers du dépôt (suivis ou non ignorés), état courant
  mkdir -p "$1"
  if [ -e "$SQ/.git" ]; then
    LISTE() { git -C "$SQ" ls-files -co --exclude-standard -z; }
  else   # lab généré (export-lab.sh) : pas de dépôt git
    LISTE() { (cd "$SQ" && find . -type f ! -path './.git/*' -print0); }
  fi
  while IFS= read -r -d '' f; do
    f="${f#./}"
    [ -f "$SQ/$f" ] || continue
    mkdir -p "$1/$(dirname "$f")"
    cp -p "$SQ/$f" "$1/$f"
  done < <(LISTE)
}

cas() {  # <nom> <contenu de TASKS.md : plein|vide>
  local D="$TMP/$1"
  copie_source "$D"
  mkdir -p "$D/config"
  if [ "$2" = plein ]; then
    printf '# Tâches\n\n## ROUND 1\nprojet: x\nbranche: claude/x\n\n- [codeur] une vraie tâche de nuit\n' > "$D/config/TASKS.md"
  else
    cp "$SQ/templates/TASKS.empty.md" "$D/config/TASKS.md"
  fi
  local SORTIE CODE
  SORTIE="$(LAB_EN_PLACE_JUSQU_A=2 bash "$D/tests/test-lab-en-place.sh" 2>&1)"; CODE=$?
  grep -E 'ECHEC|gabarit vide' <<<"$SORTIE" | sed 's/^/    | /'
  verifier "TASKS.md $2 : test-lab-en-place.sh (sections 0 à 2) code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
  verifier "TASKS.md $2 : « night.sh 1 --check (gabarit vide) » réussit" "$(grep -q '  ok   night.sh 1 --check (gabarit vide)' <<<"$SORTIE"; echo $?)"
}

echo "== config/TASKS.md rempli"
cas plein plein
echo "== config/TASKS.md vide"
cas vide vide

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
