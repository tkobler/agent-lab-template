#!/usr/bin/env bash
# Réglages par défaut de install.sh (modèle 1 du 24/10 : le lab tourne dans le clone du dépôt) : installation EN PLACE,
# projets/worktrees/logs sous <lab>/data/, racine des permissions = le lab. Tout se passe sous un faux HOME (mktemp).
# Usage : test-install-defaut.sh        Code de sortie : 0 = tous les contrôles passent.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-defaut.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
nouveau_home() { H="$TMP/$1"; mkdir -p "$H"; }   # <nom> : faux HOME vide dans $H
inst() { HOME="$H" bash "$ICI/install-en-place.sh" "$@" --brew-bin /usr/bin 2>&1; }   # <lab> [options]

echo "== cas 1 : défauts"
nouveau_home h1; L="$TMP/c1/lab"
SORTIE="$(inst "$L")"; CODE=$?
verifier "code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "installé en place (scripts exécutables, config.env, .claude/settings.json)" \
  "$([ -x "$L/scripts/night.sh" ] && [ -f "$L/config.env" ] && [ -f "$L/.claude/settings.json" ]; echo $?)"
verifier "data/projects, data/worktrees et data/logs créés" "$([ -d "$L/data/projects" ] && [ -d "$L/data/worktrees" ] && [ -d "$L/data/logs" ]; echo $?)"
verifier "config.env : LAB, RACINE, PROJETS, WORKTREES et LOGS par défaut" \
  "$(c="$L/config.env"; grep -q "^LAB=\"$L\"" "$c" && grep -q "^RACINE=\"$L\"" "$c" && grep -q "^PROJETS=\"$L/data/projects\"" "$c" && grep -q "^WORKTREES=\"$L/data/worktrees\"" "$c" && grep -q "^LOGS=\"$L/data/logs\"" "$c"; echo $?)"
verifier "aucun dossier frère créé à côté du lab (ni projets, ni worktrees, ni logs à la racine)" \
  "$([ "$(ls -A "$TMP/c1" | tr '\n' ' ')" = "lab " ] && [ ! -e "$L/logs" ] && [ ! -e "$L/projects" ] && [ ! -e "$L/worktrees" ]; echo $?)"
verifier "HOME intact" "$([ -z "$(ls -A "$H")" ]; echo $?)"
verifier "night.sh 1 --check fonctionne" "$(HOME="$H" bash "$L/scripts/night.sh" 1 --check >/dev/null 2>&1; echo $?)"
verifier "pas de dossier cible : le message annonce l'installation en place" "$(grep -q 'en place' <<<"$SORTIE"; echo $?)"

echo "== cas 2 : une option explicite gagne sur le défaut"
nouveau_home h2; L="$TMP/c2/lab"
inst "$L" --worktrees "$TMP/wt2" --projects "$TMP/pr2" --root "$TMP/r2" >/dev/null; CODE=$?
verifier "code 0, dossiers explicites créés, rien dans data/worktrees ni data/projects" \
  "$([ "$CODE" -eq 0 ] && [ -d "$TMP/wt2" ] && [ -d "$TMP/pr2" ] && [ ! -e "$L/data/worktrees" ] && [ ! -e "$L/data/projects" ]; echo $?)"
verifier "config.env porte les valeurs explicites" \
  "$(grep -q "^WORKTREES=\"$TMP/wt2\"" "$L/config.env" && grep -q "^PROJETS=\"$TMP/pr2\"" "$L/config.env" && grep -q "^RACINE=\"$TMP/r2\"" "$L/config.env"; echo $?)"

echo "== cas 3 : réinstallation en place -> config.env, memory/ et config/ jamais écrasés"
nouveau_home h3; L="$TMP/c3/lab"
inst "$L" >/dev/null
echo '# réglage local' >> "$L/config.env"
echo 'note à la main' >> "$L/memory/lab/lab-Log.md"
echo 'maison' > "$L/memory/Home.md"
echo 'mes tâches' > "$L/config/TASKS.md"
inst "$L" >/dev/null; CODE=$?
verifier "réinstallation : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "config.env conservé" "$(grep -q '# réglage local' "$L/config.env"; echo $?)"
verifier "memory/lab/lab-Log.md conservé" "$(grep -q 'note à la main' "$L/memory/lab/lab-Log.md"; echo $?)"
verifier "memory/Home.md conservé" "$([ "$(cat "$L/memory/Home.md")" = maison ]; echo $?)"
verifier "config/TASKS.md conservé" "$([ "$(cat "$L/config/TASKS.md")" = 'mes tâches' ]; echo $?)"

echo "== cas limites"
nouveau_home h4; L="$TMP/c4/lab"
inst "$L" >/dev/null
HOME="$H" bash "$L/install.sh" --bogus >/dev/null 2>&1; CODE=$?
verifier "option inconnue : code 2" "$([ "$CODE" -eq 2 ]; echo $?)"
HOME="$H" bash "$L/install.sh" "$TMP/ailleurs" --brew-bin /usr/bin >/dev/null 2>&1; CODE=$?
verifier "dossier cible donné : refusé (code 2), rien créé ailleurs" "$([ "$CODE" -eq 2 ] && [ ! -e "$TMP/ailleurs" ]; echo $?)"
HOME="$H" bash "$L/install.sh" --root >/dev/null 2>&1; CODE=$?
verifier "option sans valeur : refusée (code non nul)" "$([ "$CODE" -ne 0 ]; echo $?)"
HOME="$H" bash "$L/install.sh" --projects '/tmp/a"b' --brew-bin /usr/bin >/dev/null 2>&1; CODE=$?
verifier "chemin avec guillemet : refusé (code 1)" "$([ "$CODE" -eq 1 ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
