#!/usr/bin/env bash
# Usage : add-project-memory.sh <nom-du-projet>
# Crée memory/<nom>/ avec les notes <nom>-{Project,Agent-Knowledge,Decisions,Log}.md, tirées des gabarits
# templates/note-*.empty.md (<projet> remplacé par le nom), et ajoute la ligne du projet au tableau de memory/Home.md.
# Idempotent : une note ou une ligne existante n'est jamais réécrite. Appelé par la skill add-project.
# Home.md sans tableau : avertissement sur stderr, Home.md inchangé, code 0.
# Code de sortie : 0 = fait, 1 = nom invalide ou gabarit absent, 2 = usage.
set -euo pipefail
NOM="${1:-}"
[ -n "$NOM" ] || { echo "Usage : add-project-memory.sh <nom-du-projet>" >&2; exit 2; }
if ! [[ "$NOM" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "Nom de projet invalide « $NOM » : minuscules, chiffres et tirets seulement, sans tiret en tête." >&2
  exit 1
fi
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES="Project Agent-Knowledge Decisions Log"
for n in $NOTES; do
  [ -f "$LAB/templates/note-$n.empty.md" ] || { echo "Gabarit absent : templates/note-$n.empty.md" >&2; exit 1; }
done

mkdir -p "$LAB/memory/$NOM"
for n in $NOTES; do
  f="$LAB/memory/$NOM/$NOM-$n.md"
  if [ -f "$f" ]; then
    echo "  conservé : memory/$NOM/$NOM-$n.md"
  else
    sed "s/<projet>/$NOM/g" "$LAB/templates/note-$n.empty.md" > "$f"
    echo "  créé     : memory/$NOM/$NOM-$n.md"
  fi
done

# Tableau de memory/Home.md (Rang | Projet | Pages) : une ligne par projet, ajoutée à la fin du tableau avec le rang
# suivant (plus grand rang existant + 1), jamais en double. Sans tableau : avertissement, Home.md inchangé, code 0.
HOME_MD="$LAB/memory/Home.md"
if [ -f "$HOME_MD" ] && ! grep -qE "^\| ([0-9]+ \| )?$NOM( |:|\|)" "$HOME_MD"; then
  if ! grep -q '^|' "$HOME_MD"; then
    echo "  avertissement : memory/Home.md n'a pas de tableau, ligne de $NOM non ajoutée (à ajouter à la main)" >&2
  else
    RANG="$(awk -F'|' '/^\|/ { r = $2; gsub(/ /, "", r); if (r ~ /^[0-9]+$/ && r + 0 > max) max = r + 0 } END { print max + 1 }' "$HOME_MD")"
    LIGNE="| $RANG | $NOM | [[$NOM/$NOM-Agent-Knowledge]] · [[$NOM/$NOM-Project]] · [[$NOM/$NOM-Decisions]] · [[$NOM/$NOM-Log]] |"
    TMP="$(mktemp "${TMPDIR:-/tmp}/home-md.XXXXXX")"
    awk -v ligne="$LIGNE" '
      { lignes[NR] = $0; if ($0 ~ /^\|/) dernier = NR }
      END { for (i = 1; i <= NR; i++) { print lignes[i]; if (i == dernier) print ligne } }
    ' "$HOME_MD" > "$TMP"
    cat "$TMP" > "$HOME_MD"; rm -f "$TMP"
    echo "  ligne ajoutée à memory/Home.md (rang $RANG)"
  fi
fi
