#!/usr/bin/env bash
# Modèle « le lab tourne dans le clone du dépôt » (décision du 24/10) : de bout en bout, avec un dépôt distant NU local
# (mktemp -d /tmp/…) et un faux HOME. Aucun accès réseau, rien ne touche au vrai HOME, au vrai dépôt ni à ~/Library.
#   1. clone + install.sh en place -> « git status » vide (tout ce qui est propre à la machine est ignoré) ;
#   2. night.sh 1 --check fonctionne dans le clone ;
#   3. morning.sh pousse un changement de memory/ sur main, mais jamais un changement de scripts/ ;
#   4. morning.sh sur une autre branche : ni commit ni push ; commits de code non poussés : pas de push ;
#   5. export-lab.sh : code 0.
# tmux, launchctl et flock sont doublés (dossier passé à --brew-bin) : morning.sh ne pilote rien de réel.
# Usage : test-lab-en-place.sh        Code de sortie : 0 = tous les contrôles passent. Nécessite macOS (date -v).
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans morning.sh et night.sh)."; exit 0; fi
TMP="$(mktemp -d /tmp/test-lab-en-place.XXXXXX)"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0; SKIP=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME"
BARE="$TMP/distant.git"
FAKEBIN="$TMP/bin"; APPELS="$TMP/appels.log"; mkdir -p "$FAKEBIN"; : > "$APPELS"
for cmd in tmux launchctl; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$cmd" "$APPELS" > "$FAKEBIN/$cmd"
done
printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/flock"
chmod +x "$FAKEBIN"/*

# --- dépôt de départ = état courant du dépôt (modifications non commitées comprises), poussé sur le distant nu
git init -q --bare -b main "$BARE"
COPIER_DONNEES=1 SANS_INSTALL=1 bash "$ICI/install-en-place.sh" "$TMP/graine"
# Le test possède son config/TASKS.md : gabarit vide, jamais celui du vrai lab (qui peut contenir une nuit planifiée).
cp "$SQ/templates/TASKS.empty.md" "$TMP/graine/config/TASKS.md"
git -C "$TMP/graine" add -A
git -C "$TMP/graine" -c user.name=Essai -c user.email=essai@exemple.com commit -q -m "TASKS.md de test (gabarit vide)" || true
git -C "$TMP/graine" remote add origin "$BARE"
git -C "$TMP/graine" push -q origin main
POSSEDE_DONNEES=0
[ -f "$SQ/memory/Home.md" ] && [ -f "$SQ/config/TASKS.md" ] && POSSEDE_DONNEES=1

cloner() {  # <nom> : clone du distant + identité git locale + install.sh en place (faux HOME) ; le lab est $TMP/<nom>
  git clone -q "$BARE" "$TMP/$1" 2>/dev/null
  git -C "$TMP/$1" config user.name Essai
  git -C "$TMP/$1" config user.email essai@exemple.com
  HOME="$FAUXHOME" bash "$TMP/$1/install.sh" --brew-bin "$FAKEBIN" --prefix com.exemple >/dev/null 2>&1
}
distant() { git --git-dir="$BARE" "$@"; }

echo "== 0. install.sh et les scripts sont suivis avec le droit d'exécution (sinon le chmod de l'installation salirait git status)"
if [ -e "$SQ/.git" ]; then
  MODES="$(git -C "$SQ" ls-files -s -- install.sh 'scripts/*.sh' | awk '$1 != "100755" {print $4}')"
  [ -z "$MODES" ] || echo "$MODES" | sed 's/^/    | non exécutable dans l index : /'
  verifier "install.sh et scripts/*.sh en mode 100755 dans l'index" "$([ -z "$MODES" ]; echo $?)"
else
  SKIP=$((SKIP + 1)); echo "  SKIP modes de l'index : pas de dépôt git ici"
fi

echo "== 1. clone + install.sh en place -> git status vide"
L="$TMP/lab1"
SORTIE="$(git clone -q "$BARE" "$L" 2>&1)"; CODE=$?
verifier "clone du distant : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
SORTIE="$(HOME="$FAUXHOME" bash "$L/install.sh" --brew-bin "$FAKEBIN" --prefix com.exemple 2>&1)"; CODE=$?
verifier "install.sh en place : code 0, sans dossier cible" "$([ "$CODE" -eq 0 ] && grep -q 'en place' <<<"$SORTIE"; echo $?)"
if [ "$POSSEDE_DONNEES" = 1 ]; then
  git -C "$L" status --porcelain | sed 's/^/    | /'      # vide si tout va bien
  verifier "git status --porcelain vide après l'installation" "$([ -z "$(git -C "$L" status --porcelain)" ]; echo $?)"
else
  SKIP=$((SKIP + 1)); echo "  SKIP git status vide : cette source n'a ni memory/ ni config/ suivis (lab publiable : ils sont générés puis à commiter)"
fi
verifier "fichiers propres à la machine générés : .claude/settings.json, launchagents/*.plist, config.env" \
  "$([ -f "$L/.claude/settings.json" ] && [ -f "$L/launchagents/com.exemple.night.plist" ] && [ -f "$L/config.env" ]; echo $?)"
ignores=0
for p in .claude/settings.json launchagents/com.exemple.night.plist config.env data/projects/x data/worktrees/x data/logs/x.log .review-done; do
  git -C "$L" check-ignore -q "$p" || { ignores=1; echo "    | non ignoré : $p"; }
done
verifier "…et tous ignorés par git (aussi data/projects, data/worktrees, data/logs, .review-done)" "$ignores"
ignores=0
for p in memory/lab/lab-Log.md config/TASKS.md config/projects/demo.env reports/2026-01-01/round-1.md scripts/night.sh CLAUDE.md; do
  git -C "$L" check-ignore -q "$p" && { ignores=1; echo "    | ignoré à tort : $p"; }
done
verifier "memory/, config/, reports/, scripts/ et CLAUDE.md ne sont PAS ignorés" "$ignores"
verifier "data/projects, data/worktrees, data/logs existent" "$([ -d "$L/data/projects" ] && [ -d "$L/data/worktrees" ] && [ -d "$L/data/logs" ]; echo $?)"
verifier "config.env : LAB = le clone, projets et worktrees sous data/" \
  "$(grep -q "^LAB=\"$L\"" "$L/config.env" && grep -q "^PROJETS=\"$L/data/projects\"" "$L/config.env" && grep -q "^WORKTREES=\"$L/data/worktrees\"" "$L/config.env"; echo $?)"
verifier "CLAUDE.md, scripts/, agents/, prompts/ : aucun chemin du clone ni marqueur @…@" \
  "$(! grep -rqE -e "$L" -e '@[A-Z][A-Z_]*@' "$L/CLAUDE.md" "$L/scripts" "$L/agents" "$L/prompts"; echo $?)"
verifier "settings.json généré porte le chemin de la machine (et lui seul)" \
  "$(grep -qF "$(printf '%s' "$L" | sed 's#^/##')" "$L/.claude/settings.json" && ! git -C "$L" ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1; echo $?)"
verifier "faux HOME intact (ni Library ni LaunchAgents)" "$([ -z "$(ls -A "$FAUXHOME")" ]; echo $?)"
SORTIE="$(HOME="$FAUXHOME" bash "$L/install.sh" --brew-bin "$FAKEBIN" --prefix com.exemple 2>&1)"; CODE=$?
verifier "réinstallation en place : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
if [ "$POSSEDE_DONNEES" = 1 ]; then
  verifier "…et git status toujours vide" "$([ -z "$(git -C "$L" status --porcelain)" ]; echo $?)"
fi

echo "== 2. night.sh --check dans le clone"
SORTIE="$(HOME="$FAUXHOME" bash "$L/scripts/night.sh" 1 --check 2>&1)"; CODE=$?
verifier "night.sh 1 --check (gabarit vide) : code 0 et « aucune tâche »" "$([ "$CODE" -eq 0 ] && grep -q 'aucune tâche' <<<"$SORTIE"; echo $?)"
PROJ="$L/data/projects/demo"
mkdir -p "$PROJ"
git -C "$PROJ" init -q -b main
git -C "$PROJ" -c user.name=Essai -c user.email=essai@exemple.com commit -q --allow-empty -m init
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$PROJ" > "$L/config/projects/demo.env"
printf '# Tâches\n\n## ROUND 1\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Première tâche\n' > "$L/config/TASKS.md"
# reports/ peut déjà contenir des rapports suivis (clone d'un lab qui a servi) : on compare avant et après --check
# (fichiers et dates), au lieu de supposer le dossier vide.
REPORTS_AVANT="$(find "$L/reports" -type f ! -name .gitkeep -exec stat -f '%N %m %z' {} + 2>/dev/null | sort)"
SORTIE="$(HOME="$FAUXHOME" bash "$L/scripts/night.sh" 1 --check 2>&1)"; CODE=$?
verifier "night.sh 1 --check avec un projet sous data/projects : code 0 et OK" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 1 : 1 tâche(s) sur « demo », branche claude/essai' <<<"$SORTIE"; echo $?)"
REPORTS_APRES="$(find "$L/reports" -type f ! -name .gitkeep -exec stat -f '%N %m %z' {} + 2>/dev/null | sort)"
verifier "…sans rien écrire dans data/logs ni reports/ (--check)" "$([ -z "$(ls -A "$L/data/logs")" ] && [ "$REPORTS_AVANT" = "$REPORTS_APRES" ]; echo $?)"
verifier "data/projects/demo est ignoré par git (pas de dépôt imbriqué dans le statut)" "$(! git -C "$L" status --porcelain | grep -q 'data/'; echo $?)"

if [ "${LAB_EN_PLACE_JUSQU_A:-}" = 2 ]; then   # usage : test-lab-en-place-isole.sh (sections 0 à 2 seulement)
  echo "Résultat : $OK réussi(s), $KO échec(s), $SKIP ignoré(s)"
  [ "$KO" -eq 0 ]; exit
fi

echo "== 3. morning.sh : un changement de memory/ est poussé sur main, un changement de scripts/ ne l'est pas"
L="$TMP/lab3"; cloner lab3
AVANT="$(distant rev-parse main)"
SCRIPT_AVANT="$(distant show main:scripts/night.sh | shasum | cut -d' ' -f1)"
echo "note de la nuit $$" >> "$L/memory/lab/lab-Log.md"
mkdir -p "$L/reports/2026-10-24"; echo "rapport essai" > "$L/reports/2026-10-24/round-1.md"
echo "# modification locale du code" >> "$L/scripts/night.sh"
: > "$APPELS"
SORTIE="$(HOME="$FAUXHOME" bash "$L/scripts/morning.sh" 2>&1)"; CODE=$?
APRES="$(distant rev-parse main)"
verifier "morning.sh : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "le distant a reçu un nouveau commit sur main" "$([ "$APRES" != "$AVANT" ] && [ "$(distant rev-list --count "$AVANT..$APRES")" -eq 1 ]; echo $?)"
verifier "memory/lab/lab-Log.md poussé" "$(distant show main:memory/lab/lab-Log.md | grep -q "note de la nuit $$"; echo $?)"
verifier "reports/ poussé" "$(distant show main:reports/2026-10-24/round-1.md | grep -q 'rapport essai'; echo $?)"
verifier "scripts/night.sh modifié : PAS poussé (identique à avant sur le distant)" "$([ "$(distant show main:scripts/night.sh | shasum | cut -d' ' -f1)" = "$SCRIPT_AVANT" ]; echo $?)"
verifier "le commit poussé ne touche que memory/ et reports/" "$([ -z "$(distant diff --name-only "$AVANT" "$APRES" | grep -vE '^(memory|config|reports)/')" ]; echo $?)"
verifier "scripts/night.sh reste modifié, non commité, dans le clone" "$(git -C "$L" status --porcelain | grep -q '^ M scripts/night.sh'; echo $?)"
verifier "la rotation du manageur a eu lieu (tmux kill-session, launchctl kickstart)" \
  "$(grep -q 'tmux kill-session -t manager' "$APPELS" && grep -q 'launchctl kickstart -k .*com.exemple.manager' "$APPELS"; echo $?)"
verifier "aucune erreur (fatal, erreur) dans la sortie de morning.sh" "$(! grep -qiE 'fatal|erreur' <<<"$SORTIE"; echo $?)"

echo "== 3 bis. seul scripts/ a changé : ni commit ni push"
AVANT="$(distant rev-parse main)"; LOCAL_AVANT="$(git -C "$L" rev-parse HEAD)"
git -C "$L" checkout -q -- memory config reports 2>/dev/null
HOME="$FAUXHOME" bash "$L/scripts/morning.sh" >/dev/null 2>&1; CODE=$?
verifier "code 0, aucun nouveau commit local ni distant" "$([ "$CODE" -eq 0 ] && [ "$(git -C "$L" rev-parse HEAD)" = "$LOCAL_AVANT" ] && [ "$(distant rev-parse main)" = "$AVANT" ]; echo $?)"
verifier "la modification de scripts/night.sh est toujours là, non commitée" "$(git -C "$L" status --porcelain | grep -q '^ M scripts/night.sh'; echo $?)"

echo "== 4. autre branche : ni commit ni push"
L="$TMP/lab4"; cloner lab4
git -C "$L" checkout -q -b claude/essai
AVANT="$(distant rev-parse main)"; LOCAL_AVANT="$(git -C "$L" rev-parse HEAD)"
echo "note sur une branche" >> "$L/memory/lab/lab-Log.md"
SORTIE="$(HOME="$FAUXHOME" bash "$L/scripts/morning.sh" 2>&1)"; CODE=$?
verifier "code 0 et message explicite" "$([ "$CODE" -eq 0 ] && grep -q 'pas main' <<<"$SORTIE"; echo $?)"
verifier "distant inchangé (main), aucune branche claude/essai créée sur le distant" "$([ "$(distant rev-parse main)" = "$AVANT" ] && ! distant rev-parse -q --verify refs/heads/claude/essai >/dev/null; echo $?)"
verifier "aucun commit local" "$([ "$(git -C "$L" rev-parse HEAD)" = "$LOCAL_AVANT" ]; echo $?)"
verifier "la note reste non commitée dans le clone" "$(git -C "$L" status --porcelain | grep -q 'memory/lab/lab-Log.md'; echo $?)"
git -C "$L" checkout -q --detach
SORTIE="$(HOME="$FAUXHOME" bash "$L/scripts/morning.sh" 2>&1)"; CODE=$?
verifier "tête détachée : code 0, ni commit ni push" "$([ "$CODE" -eq 0 ] && [ "$(git -C "$L" rev-parse HEAD)" = "$LOCAL_AVANT" ] && [ "$(distant rev-parse main)" = "$AVANT" ]; echo $?)"

echo "== 4 bis. commit de code local non poussé sur main : jamais poussé avec les données"
L="$TMP/lab5"; cloner lab5
AVANT="$(distant rev-parse main)"
echo "# code commité à la main" >> "$L/scripts/night.sh"
git -C "$L" commit -qam "feat: code local"
echo "note de données" >> "$L/memory/lab/lab-Log.md"
SORTIE="$(HOME="$FAUXHOME" bash "$L/scripts/morning.sh" 2>&1)"; CODE=$?
verifier "code 0, message « touchent du code », distant inchangé" "$([ "$CODE" -eq 0 ] && grep -q 'touchent du code' <<<"$SORTIE" && [ "$(distant rev-parse main)" = "$AVANT" ]; echo $?)"
verifier "la note est tout de même commitée en local" "$(git -C "$L" log -1 --format=%s | grep -q 'nuit du'; echo $?)"

echo "== 4 ter. aucun changement et pas de remote joignable"
L="$TMP/lab6"; cloner lab6
AVANT="$(distant rev-parse main)"; LOCAL_AVANT="$(git -C "$L" rev-parse HEAD)"
HOME="$FAUXHOME" bash "$L/scripts/morning.sh" >/dev/null 2>&1; CODE=$?
verifier "rien à sauvegarder : code 0, pas de commit vide" "$([ "$CODE" -eq 0 ] && [ "$(git -C "$L" rev-parse HEAD)" = "$LOCAL_AVANT" ] && [ "$(distant rev-parse main)" = "$AVANT" ]; echo $?)"
git -C "$L" remote set-url origin "$TMP/inexistant.git"
echo "note hors ligne" >> "$L/memory/lab/lab-Log.md"
SORTIE="$(HOME="$FAUXHOME" bash "$L/scripts/morning.sh" 2>&1)"; CODE=$?
verifier "distant injoignable : code 0, commit local fait, push abandonné proprement" \
  "$([ "$CODE" -eq 0 ] && git -C "$L" log -1 --format=%s | grep -q 'nuit du' && grep -q 'fetch origin impossible' <<<"$SORTIE"; echo $?)"

echo "== 5. export-lab.sh"
SORTIE="$(bash "$SQ/scripts/export-lab.sh" "$TMP/export" 2>&1)"; CODE=$?
verifier "export-lab.sh : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "lab exporté : install.sh, .gitignore (data/ et config.env ignorés), ni memory/ ni data/" \
  "$([ -f "$TMP/export/install.sh" ] && grep -qx 'data/' "$TMP/export/.gitignore" && grep -qx 'config.env' "$TMP/export/.gitignore" && [ ! -e "$TMP/export/memory" ] && [ ! -e "$TMP/export/data" ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s), $SKIP ignoré(s)"
[ "$KO" -eq 0 ]
