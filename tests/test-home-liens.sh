#!/usr/bin/env bash
# Vérifie que chaque lien [[…]] de memory/Home.md du lab installé (faux lab) pointe vers une note existante
# (racine du coffre = memory/, [[a/b]] -> memory/a/b.md, alias |… et ancre #… ignorés).
# Un second passage prouve que le test devient ROUGE quand un lien est cassé (note supprimée, lien inventé).
# Sécurité : HOME remplacé par un dossier vide, installation dans un dossier temporaire.
# Usage : test-home-liens.sh        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-home-liens.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME"
LAB="$TMP/racine/lab"
OK=0; KO=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
# liens_casses <dossier memory> : affiche chaque lien de Home.md sans note ; code 0 si aucun, 1 sinon
liens_casses() {
  local mem="$1" nbcass=0 lien cible
  while IFS= read -r lien; do
    cible="${lien%%|*}"; cible="${cible%%#*}"
    [ -f "$mem/$cible.md" ] || { echo "    lien cassé : [[$lien]]"; nbcass=$((nbcass + 1)); }
  done < <(grep -o '\[\[[^]]*\]\]' "$mem/Home.md" | sed 's/^\[\[//; s/\]\]$//')
  [ "$nbcass" -eq 0 ]
}

echo "== installation du faux lab"
HOME="$FAUXHOME" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
verifier "install.sh : code 0" "$?"
verifier "memory/Home.md installé" "$([ -f "$LAB/memory/Home.md" ]; echo $?)"
verifier "Home.md contient au moins un lien [[…]]" "$([ "$(grep -o '\[\[[^]]*\]\]' "$LAB/memory/Home.md" | wc -l)" -ge 1 ]; echo $?)"

echo "== liens de Home.md du lab installé"
liens_casses "$LAB/memory"
verifier "tous les liens de Home.md pointent vers une note existante" "$?"

echo "== cas cassé : le test doit devenir rouge"
rm "$LAB/memory/lab/lab-Log.md"
liens_casses "$LAB/memory" >/dev/null
verifier "note supprimée (lab-Log) : lien cassé détecté" "$([ "$?" -eq 1 ]; echo $?)"
HOME="$FAUXHOME" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
echo '| 9 | x | [[inexistant/page|alias]] |' >> "$LAB/memory/Home.md"
liens_casses "$LAB/memory" >/dev/null
verifier "lien inventé avec alias : détecté" "$([ "$?" -eq 1 ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
