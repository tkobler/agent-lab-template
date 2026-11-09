#!/usr/bin/env bash
# Teste l'ajout d'un projet dans un faux lab (D2 et D3 du 21/10) :
#   - scripts/add-project-memory.sh <nom> crée memory/<nom>/ à partir des gabarits templates/note-*.empty.md ;
#   - la ligne du projet est ajoutée au tableau de memory/Home.md ; rien n'est jamais écrasé ; noms invalides refusés ;
#   - .review-done est ignoré par git dans le LAB installé ; la skill add-project appelle le script.
# Sécurité : HOME remplacé par un dossier vide, tout est installé dans un dossier temporaire.
# Usage : test-add-project.sh        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-add-project.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME"
LAB="$TMP/racine/lab"
OK=0; KO=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
colonnes() {  # <ligne> : nombre de colonnes d'une ligne de tableau
  echo "$1" | awk -F'|' '{print NF - 2}'
}
ajouter() { HOME="$FAUXHOME" bash "$LAB/scripts/add-project-memory.sh" "$@" 2>&1; }

echo "== installation du faux lab"
HOME="$FAUXHOME" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
verifier "install.sh : code 0" "$?"
verifier "scripts/add-project-memory.sh installé et exécutable" "$([ -x "$LAB/scripts/add-project-memory.sh" ]; echo $?)"

echo "== .review-done ignoré par git (D3)"
verifier ".gitignore du lab installé contient .review-done" "$(grep -qx '.review-done' "$LAB/.gitignore"; echo $?)"
verifier "git check-ignore .review-done : ignoré" "$(git -C "$LAB" check-ignore -q .review-done; echo $?)"
verifier "memory/Home.md n'est pas ignoré (sanité)" "$(! git -C "$LAB" check-ignore -q memory/Home.md; echo $?)"

echo "== Home.md installé : tableau à 3 colonnes (Rang | Projet | Pages)"
verifier "gabarit : en-tête Rang | Projet | Pages" "$(grep -qE '^\| Rang \| Projet \| Pages \|$' "$LAB/templates/note-Home.empty.md"; echo $?)"
verifier "Home.md installé : en-tête Rang | Projet | Pages" "$(grep -qE '^\| Rang \| Projet \| Pages \|$' "$LAB/memory/Home.md"; echo $?)"
verifier "Home.md installé : toutes les lignes du tableau ont 3 colonnes" \
  "$([ "$(grep '^|' "$LAB/memory/Home.md" | while IFS= read -r l; do colonnes "$l"; done | sort -u | tr -d '\n')" = 3 ]; echo $?)"
verifier "Home.md installé : ligne lab de rang 1" "$(grep -qE '^\| 1 \| lab' "$LAB/memory/Home.md"; echo $?)"

echo "== ajout du projet « demo-app »"
SORTIE="$(ajouter demo-app)"; CODE=$?
verifier "add-project-memory.sh demo-app : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "memory/demo-app/ créé avec Project, Agent-Knowledge, Decisions et Log" \
  "$(for n in Project Agent-Knowledge Decisions Log; do [ -f "$LAB/memory/demo-app/demo-app-$n.md" ] || exit 1; done; echo $?)"
verifier "uniquement ces 4 notes (pas de Running, propre au lab)" "$([ "$(ls "$LAB/memory/demo-app" | wc -l | tr -d ' ')" -eq 4 ]; echo $?)"
verifier "aucun <projet> restant, le nom du projet est dans chaque note" \
  "$(! grep -rqF '<projet>' "$LAB/memory/demo-app" && for f in "$LAB"/memory/demo-app/*.md; do grep -q 'demo-app' "$f" || exit 1; done; echo $?)"
verifier "contenu = gabarit (Decisions : mêmes lignes que le gabarit hors nom)" \
  "$(diff <(sed 's/<projet>/demo-app/g' "$LAB/templates/note-Decisions.empty.md") "$LAB/memory/demo-app/demo-app-Decisions.md" >/dev/null; echo $?)"
verifier "Home.md : une ligne du tableau pour demo-app, avec liens vers ses notes" \
  "$(grep -E '^\| [0-9]+ \| demo-app' "$LAB/memory/Home.md" | grep -qF '[[demo-app/demo-app-Project]]'; echo $?)"
verifier "Home.md : demo-app a le rang 2, sur 3 colonnes" \
  "$(L="$(grep -E '^\| [0-9]+ \| demo-app' "$LAB/memory/Home.md")"; [[ "$L" == '| 2 | demo-app'* ]] && [ "$(colonnes "$L")" = 3 ]; echo $?)"
verifier "Home.md : ligne lab conservée" "$(grep -qF '[[lab/lab-Project]]' "$LAB/memory/Home.md"; echo $?)"

echo "== idempotence : rien n'est écrasé"
echo 'note ajoutée à la main' >> "$LAB/memory/demo-app/demo-app-Log.md"
SORTIE="$(ajouter demo-app)"; CODE=$?
verifier "deuxième appel : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "note existante conservée" "$(grep -q 'note ajoutée à la main' "$LAB/memory/demo-app/demo-app-Log.md"; echo $?)"
verifier "Home.md : toujours une seule ligne demo-app" "$([ "$(grep -cE '^\| [0-9]+ \| demo-app' "$LAB/memory/Home.md")" -eq 1 ]; echo $?)"
rm "$LAB/memory/demo-app/demo-app-Project.md"
ajouter demo-app >/dev/null
verifier "note supprimée : recréée, les autres inchangées" \
  "$([ -f "$LAB/memory/demo-app/demo-app-Project.md" ] && grep -q 'note ajoutée à la main' "$LAB/memory/demo-app/demo-app-Log.md"; echo $?)"

echo "== un second projet et les valeurs refusées"
ajouter autre2 >/dev/null
verifier "second projet : memory/autre2/autre2-Project.md et ligne dans Home.md" \
  "$([ -f "$LAB/memory/autre2/autre2-Project.md" ] && grep -qE '^\| 3 \| autre2' "$LAB/memory/Home.md"; echo $?)"
verifier "rangs consécutifs 1, 2, 3 et toutes les lignes à 3 colonnes" \
  "$([ "$(grep -E '^\| [0-9]+ \|' "$LAB/memory/Home.md" | awk -F'|' '{gsub(/ /,"",$2); printf "%s%s", $2, (NF==5 ? "," : "!")}')" = "1,2,3," ]; echo $?)"

echo "== Home.md sans tableau : avertissement, rien de cassé (code 0, aucune ligne ajoutée)"
printf '# Accueil\n\nPas de tableau ici.\n' > "$LAB/memory/Home.md"
cp "$LAB/memory/Home.md" "$TMP/home-sans-tableau.md"
SORTIE="$(ajouter sans-tab)"; CODE=$?
verifier "code 0, notes créées" "$([ "$CODE" -eq 0 ] && [ -f "$LAB/memory/sans-tab/sans-tab-Project.md" ]; echo $?)"
verifier "avertissement affiché" "$(echo "$SORTIE" | grep -qi 'avertissement'; echo $?)"
verifier "Home.md inchangé" "$(cmp -s "$LAB/memory/Home.md" "$TMP/home-sans-tableau.md"; echo $?)"

ajouter >/dev/null; CODE=$?
verifier "sans argument : code 2" "$([ "$CODE" -eq 2 ]; echo $?)"
for mauvais in 'Majuscule' 'avec espace' '../evasion' 'a/b' '-tiret' 'x;y' '.'; do
  AVANT="$(ls "$LAB/memory" | tr '\n' ' ')"
  ajouter "$mauvais" >/dev/null; CODE=$?
  verifier "nom « $mauvais » refusé (code 1), rien créé" "$([ "$CODE" -eq 1 ] && [ "$(ls "$LAB/memory" | tr '\n' ' ')" = "$AVANT" ] && [ ! -e "$LAB/evasion" ]; echo $?)"
done
verifier "HOME de substitution intact" "$([ -z "$(ls -A "$FAUXHOME")" ]; echo $?)"

echo "== la skill add-project"
S="$SQ/claude/skills/add-project/SKILL.md"
verifier "la skill appelle scripts/add-project-memory.sh" "$(grep -qF 'scripts/add-project-memory.sh' "$S"; echo $?)"
verifier "la skill cite les gabarits templates/note-*.empty.md" "$(grep -qF 'note-*.empty.md' "$S"; echo $?)"
verifier "la skill ne liste plus de notes sans gabarit (Tasks, Ideas)" "$(! grep -qE '<nom>-(Tasks|Ideas)' "$S"; echo $?)"
verifier "settings.json de la source ne mentionne pas le script (D1 B : validation manuelle gardée)" \
  "$(! grep -q 'add-project-memory' "$SQ/claude/settings.json"; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
