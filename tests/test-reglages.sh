#!/usr/bin/env bash
# Teste les réglages de permissions du manageur : claude/settings.json (modèle avec marqueurs) est installé par
# install.sh dans <LAB>/.claude/settings.json avec les chemins de la machine, et ses garde-fous sont ceux du lab réel.
# Référence facultative : 1er argument ou REGLAGES_LAB_REFERENCE=<chemin du .claude/settings.json du lab réel> (lecture seule). Quand il est
# donné, le fichier installé dans un faux lab placé sous un faux HOME à la même disposition (noms de la racine et du lab lus dans la référence,
# projets, worktrees) doit lui être identique octet pour octet : « identiques aux marqueurs près ».
# Sécurité : HOME est remplacé par un dossier temporaire ; rien n'est écrit hors de ce dossier.
# Usage : test-reglages.sh [settings.json de référence]        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
SRC="$SQ/claude/settings.json"
source "$ICI/anciens-noms.sh"      # anciens noms français, assemblés
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-reglages.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0; SKIP=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
json_valide() { python3 -I -c 'import json,sys; json.load(open(sys.argv[1]))' "$1" 2>/dev/null; }
liste() {  # <fichier> <allow|deny> : une entrée par ligne
  python3 -I -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"][sys.argv[2]]))' "$1" "$2"
}

echo "== le modèle de réglages (claude/settings.json)"
verifier "claude/settings.json existe" "$([ -f "$SRC" ]; echo $?)"
verifier "JSON valide" "$(json_valide "$SRC"; echo $?)"
verifier "mode par défaut inchangé (auto)" "$([ "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["permissions"]["defaultMode"])' "$SRC" 2>/dev/null)" = auto ]; echo $?)"
verifier "6 lignes à marqueurs de chemin (1 Read, 3 Edit autorisés, 2 Edit interdits), pas une de plus" \
  "$([ "$(grep -cE '@(RACINE|LAB|PROJETS|WORKTREES)_PERM@' "$SRC")" -eq 6 ]; echo $?)"
verifier "marqueurs attendus : Read racine, Edit LAB, Edit projets et worktrees interdits" \
  "$(grep -q '"Read(@RACINE_PERM@/\*\*)"' "$SRC" && grep -q '"Edit(@LAB_PERM@/config/TASKS.md)"' "$SRC" && grep -q '"Edit(@LAB_PERM@/config/NOW.md)"' "$SRC" \
     && grep -q '"Edit(@LAB_PERM@/memory/\*\*)"' "$SRC" && grep -q '"Edit(@PROJETS_PERM@/\*\*)"' "$SRC" && grep -q '"Edit(@WORKTREES_PERM@/\*\*)"' "$SRC"; echo $?)"

echo "== installation dans un faux lab à la disposition du lab réel (sous un faux HOME)"
REF="${1:-${REGLAGES_LAB_REFERENCE:-}}"
RN="racine-x"; HN="lab-x"          # noms par défaut ; avec une référence, ceux du lab réel (pour obtenir le même fichier)
if [ -n "$REF" ] && [ -f "$REF" ]; then
  RN="$(sed -n 's#^.*"Read(~/\([^/]*\)/\*\*)".*$#\1#p' "$REF" | head -n 1)"
  # La référence (lab réel) peut avoir l'ancien nom du fichier de tâches ou le nouveau config/TASKS.md
  HN="$(sed -n -E "s#^.*\"Edit\(~/[^/]*/([^/]*)/(${AN_TASKS_UP}\.md|config/TASKS\.md)\)\".*\$#\1#p" "$REF" | head -n 1)"
  [ -n "$RN" ] && [ -n "$HN" ] || { RN="racine-x"; HN="lab-x"; }
fi
FH="$TMP/home"; LAB="$FH/$RN/$HN"; mkdir -p "$FH"
SORTIE="$(HOME="$FH" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple 2>&1)"; CODE=$?
verifier "install.sh : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "settings.json installé dans <LAB>/.claude/" "$([ -f "$LAB/.claude/settings.json" ]; echo $?)"
verifier "aucun avertissement ATTENTION ni SKIP" "$(! grep -qE 'ATTENTION|SKIP' <<<"$SORTIE"; echo $?)"
verifier "aucun marqueur restant" "$(! grep -q '@[A-Z_]*@' "$LAB/.claude/settings.json"; echo $?)"
verifier "JSON valide après rendu" "$(json_valide "$LAB/.claude/settings.json"; echo $?)"
verifier "aucun ancien nom (fichiers de tâches, $AN_RAPPORTS, scripts, option) dans les réglages installés" \
  "$(! grep -qE "${AN_TASKS_UP}|${AN_NOW_UP}|${AN_RAPPORTS}|${AN_NUIT_SH//./\\.}|${AN_VERIFIER}|${AN_RUNNOW_SH%.sh}|${AN_DIRECTE_SH%.sh}" "$LAB/.claude/settings.json"; echo $?)"
verifier "chemins en forme ~/… (LAB sous HOME)" \
  "$(grep -qF "\"Read(~/$RN/$HN/**)\"" "$LAB/.claude/settings.json" && grep -qF "\"Edit(~/$RN/$HN/config/TASKS.md)\"" "$LAB/.claude/settings.json" \
     && grep -qF "\"Edit(~/$RN/$HN/data/projects/**)\"" "$LAB/.claude/settings.json" && grep -qF "\"Edit(~/$RN/$HN/data/worktrees/**)\"" "$LAB/.claude/settings.json"; echo $?)"

# Garde-fous attendus, écrits ici en dur : ils ne doivent pas bouger sans décision de l'utilisateur.
DENY_ATTENDU="Edit(~/$RN/$HN/data/projects/**)
Edit(~/$RN/$HN/data/worktrees/**)
Bash(git push*)
Bash(git -C * push*)
Bash(git -C * commit*)
Bash(git -C * reset*)
Bash(git -C * merge*)
Bash(gh pr merge*)
Bash(gh repo delete*)
Bash(gh repo archive*)
Bash(gh api -X DELETE*)
Bash(gh api --method DELETE*)
Bash(rm -rf*)
Bash(sudo *)"
verifier "liste deny identique aux garde-fous du lab (14 interdits, même ordre)" "$([ "$(liste "$LAB/.claude/settings.json" deny)" = "$DENY_ATTENDU" ]; echo $?)"
verifier "allow : aucune autorisation d'écriture hors config/TASKS.md, config/NOW.md, memory/" \
  "$([ "$(liste "$LAB/.claude/settings.json" allow | grep -c '^Edit(')" -eq 3 ]; echo $?)"
verifier "allow : ni push, ni merge, ni suppression, ni sudo" \
  "$([ -n "$(liste "$LAB/.claude/settings.json" allow 2>/dev/null)" ] && ! liste "$LAB/.claude/settings.json" allow | grep -qE 'push|merge|delete|rm |sudo|commit|reset'; echo $?)"

if [ -n "$REF" ] && [ -f "$REF" ]; then
  # Le lab réel porte encore les anciens noms : ils sont ramenés aux nouveaux (table de tests/anciens-noms.sh) avant la comparaison.
  REFNOM="$(cat "$REF")"
  for paire in "scripts/${AN_NUIT_SH} * ${AN_VERIFIER}|scripts/night.sh * --check" "scripts/${AN_RUNNOW_SH}|scripts/run-now.sh" \
               "scripts/${AN_DIRECTE_SH}|scripts/direct-session.sh" "/${AN_TASKS_UP}.md|/config/TASKS.md" "/${AN_NOW_UP}.md|/config/NOW.md" \
               "find ${AN_RAPPORTS}|find reports"; do
    ancien="${paire%%|*}"; nouveau="${paire#*|}"
    REFNOM=${REFNOM//"$ancien"/$nouveau}
  done
  printf '%s\n' "$REFNOM" > "$TMP/reference-renommee.json"
  verifier "identique au settings.json du lab réel (octet pour octet, aux marqueurs et aux renommages près)" "$(cmp -s "$TMP/reference-renommee.json" "$LAB/.claude/settings.json"; echo $?)"
else
  SKIP=$((SKIP + 1)); echo "  SKIP comparaison au lab réel : REGLAGES_LAB_REFERENCE non défini (fichier de référence absent)"
fi

echo "== autre disposition : LAB hors du dossier personnel (forme //chemin absolu)"
LAB2="$TMP/ailleurs/lab"
HOME="$FH" bash "$ICI/install-en-place.sh" "$LAB2" --brew-bin /usr/bin >/dev/null 2>&1; CODE=$?
verifier "installation hors HOME : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "forme //chemin pour le lab, la racine, les projets et les copies de travail" \
  "$(grep -q "\"Read(/$LAB2/\*\*)\"" "$LAB2/.claude/settings.json" && grep -q "\"Edit(/$LAB2/config/TASKS.md)\"" "$LAB2/.claude/settings.json" \
     && grep -q "\"Edit(/$LAB2/data/projects/\*\*)\"" "$LAB2/.claude/settings.json" && grep -q "\"Edit(/$LAB2/data/worktrees/\*\*)\"" "$LAB2/.claude/settings.json"; echo $?)"

echo "== réinstallation"
echo '{"permissions":{"defaultMode":"bypassPermissions"}}' > "$LAB/.claude/settings.json"
HOME="$FH" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin >/dev/null 2>&1; CODE=$?
verifier "réinstallation : code 0 et réglages réécrits (modification locale perdue, comme prévu)" \
  "$([ "$CODE" -eq 0 ] && [ "$(liste "$LAB/.claude/settings.json" deny)" = "$DENY_ATTENDU" ]; echo $?)"
verifier "HOME de substitution : seul $RN y a été créé" "$([ "$(ls -A "$FH")" = "$RN" ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s), $SKIP ignoré(s)"
[ "$KO" -eq 0 ]
