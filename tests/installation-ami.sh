#!/usr/bin/env bash
# Installation à blanc, comme un nouvel utilisateur : rejoue À LA LETTRE les commandes de la partie 3 du README
# (extraites du README lui-même, pas recopiées ici), une à une, dans un dossier temporaire :
#   export neuf (scripts/export-lab.sh) -> dépôt local (git init + commit) = le « dépôt reçu » -> les blocs du README
#   (git clone <URL-DU-DEPOT> ~/agent-lab, cd, bash install.sh, scripts/night.sh 1 --check, boucle launchctl bootstrap)
# avec HOME redirigé vers le dossier temporaire et launchctl/brew/gh/claude/tmux/flock/gtimeout DOUBLÉS (faux PATH) :
# rien de réel n'est chargé ni installé, ~ n'est pas touché. Puis vérifie le résultat (memory/lab/, lab-Team.md,
# config/TASKS.md, config/NOW.md, reports/, 5 plist, message final d'install.sh = celui du README, taille du README).
# Marche depuis le dépôt de travail comme depuis un lab exporté (sans .git, sans tools/).
# Usage : bash tests/installation-ami.sh        Code de sortie : 0 = tout passe. Nécessite macOS.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
README="$SQ/README.md"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans night.sh)."; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/installation-ami.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }

FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME"
DEPOT="$TMP/depot-recu"          # ce que l'ami reçoit (l'export, devenu un dépôt git)
BIN="$TMP/bin"; APPELS="$TMP/appels.log"; mkdir -p "$BIN"; : > "$APPELS"
# Doublures : elles notent leurs appels. launchctl list répond comme si les jobs bootstrapés étaient chargés.
for cmd in brew gh claude tmux flock gtimeout caffeinate; do
  printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$cmd" "$APPELS" > "$BIN/$cmd"
done
cat > "$BIN/launchctl" <<EOF
#!/bin/sh
echo "launchctl \$*" >> "$APPELS"
if [ "\$1" = list ]; then grep -o 'com.agent-lab\.[a-z-]*' "$APPELS" | sort -u; fi
exit 0
EOF
chmod +x "$BIN"/*

echo "== 1. export neuf (bash scripts/export-lab.sh) puis dépôt local"
EXPORT="$TMP/export"
SORTIE="$(bash "$SQ/scripts/export-lab.sh" "$EXPORT" 2>&1)"; CODE=$?
echo "$SORTIE" | tail -3 | sed 's/^/    | /'
verifier "export-lab.sh : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
[ -d "$EXPORT" ] || { echo "ECHEC : pas d'export, arrêt."; exit 1; }
mv "$EXPORT" "$DEPOT"
git -C "$DEPOT" init -q -b main
git -C "$DEPOT" add -A
git -C "$DEPOT" -c user.name=Essai -c user.email=essai@exemple.com commit -q -m "depot recu"; verifier "dépôt local commité" "$?"

echo "== 2. blocs de code de la partie 3 du README, extraits tels quels"
# Blocs ``` entre « ## 3. » et « ## 4. » ; un fichier par bloc : bloc-1, bloc-2…
awk -v dir="$TMP" '
  /^## 3\./ {on=1; next}  /^## 4\./ {on=0}
  on && /^```/ {if (dedans) dedans=0; else {dedans=1; n++}; next}
  on && dedans {print > (dir "/bloc-" n)}' "$README"
NB="$(ls "$TMP"/bloc-* 2>/dev/null | wc -l | tr -d ' ')"
verifier "la partie 3 du README contient 6 blocs de code (clone+install / dépôt perso / contrôle / message / launchctl night+morning / launchctl manager) : $NB" "$([ "$NB" -eq 6 ]; echo $?)"
grep -q '<URL-DU-DEPOT>' "$TMP/bloc-1"; verifier "bloc 1 : porte le marqueur <URL-DU-DEPOT> à remplacer" "$?"

# Rejeu : une commande par ligne (les lignes du README), dans un même shell (le cd est conservé), HOME et PATH doublés.
# Seule substitution : <URL-DU-DEPOT> -> le dépôt local. Le bloc 3 est un message affiché, pas une commande.
sed "s|<URL-DU-DEPOT>|$DEPOT|" "$TMP/bloc-1" > "$TMP/rejeu-1"
for n in 2 3 5 6; do cp "$TMP/bloc-$n" "$TMP/rejeu-$n"; done
cat > "$TMP/session.sh" <<EOF
rejeu() { while IFS= read -r l; do [ -n "\$l" ] || continue; echo "\$ \$l"; eval "\$l" || { echo "    (code \$?)"; return 1; }; done < "\$1"; }
rejeu "$TMP/rejeu-1" || exit 11
echo "-- bloc 2 (dépôt personnel)"; rejeu "$TMP/rejeu-2" || exit 12
echo "-- bloc 3 (contrôle)"; rejeu "$TMP/rejeu-3" || exit 13
echo "-- bloc 5 (LaunchAgents night, morning…)"; rejeu "$TMP/rejeu-5" || exit 15
echo "-- bloc 6 (LaunchAgent manager)"; rejeu "$TMP/rejeu-6" || exit 16
EOF
echo "== 3. rejeu (HOME factice, PATH doublé)"
SORTIE="$(cd "$FAUXHOME" && HOME="$FAUXHOME" PATH="$BIN:$PATH" bash "$TMP/session.sh" 2>&1)"; CODE=$?
echo "$SORTIE" | sed "s|$TMP|<tmp>|g; s/^/    | /"
verifier "toutes les commandes du README passent (code 0)" "$([ "$CODE" -eq 0 ]; echo $?)"

L="$FAUXHOME/agent-lab"
echo "== 4. vérifications du résultat"
verifier "le clone ~/agent-lab existe avec install.sh" "$([ -f "$L/install.sh" ]; echo $?)"
verifier "config.env créé par install.sh (aucune copie manuelle de config.example.env demandée)" "$([ -f "$L/config.env" ]; echo $?)"
verifier "config.env : LAB = le clone" "$(grep -q "^LAB=\"$L\"" "$L/config.env"; echo $?)"
for d in memory/lab config/projects reports data/projects data/worktrees data/logs .claude; do
  verifier "dossier $d" "$([ -d "$L/$d" ]; echo $?)"
done
for f in memory/lab/lab-Team.md memory/Home.md config/TASKS.md config/NOW.md .claude/settings.json; do
  verifier "fichier $f" "$([ -f "$L/$f" ]; echo $?)"
done
for n in night morning morning-retry manager now; do
  verifier "launchagents/com.agent-lab.$n.plist" "$([ -f "$L/launchagents/com.agent-lab.$n.plist" ]; echo $?)"
done
verifier "le README cite les cinq noms de jobs" \
  "$(for n in night morning morning-retry manager now; do grep -q "\`\?\.\?$n\`" "$README" || exit 1; done; echo $?)"
NBP="$(ls "$L"/launchagents/*.plist | wc -l | tr -d ' ')"
verifier "exactement 5 plist (le README dit « cinq ») : $NBP" "$([ "$NBP" -eq 5 ]; echo $?)"
MSG="$(grep '^Pour en charger' "$TMP/bloc-4")"
SORTIE_INSTALL="$(cd "$L" && HOME="$FAUXHOME" PATH="$BIN:$PATH" bash install.sh 2>&1)"
verifier "le message final d'install.sh est celui que cite le README" "$([ -n "$MSG" ] && grep -qF -- "$MSG" <<<"$SORTIE_INSTALL"; echo $?)"
BOOT="$(grep -c '^launchctl bootstrap' "$APPELS")"
verifier "dépôt personnel : l'ancien origin devient upstream, gh repo create appelé avec --remote=origin --push" \
  "$(git -C "$L" remote | grep -qx upstream && grep -q '^gh repo create .*--remote=origin --push' "$APPELS"; echo $?)"
verifier "launchctl bootstrap (doublé) appelé 5 fois par les deux blocs du README : $BOOT" "$([ "$BOOT" -eq 5 ]; echo $?)"
verifier "launchctl list | grep com.agent-lab liste 5 jobs" "$([ "$(grep -c 'com.agent-lab' <<<"$SORTIE")" -ge 5 ]; echo $?)"
ls "$FAUXHOME/Library/LaunchAgents"/com.agent-lab.*.plist >/dev/null 2>&1; verifier "les plist ont été copiés dans le (faux) ~/Library/LaunchAgents" "$?"
verifier "options citées par le README = celles d'install.sh" \
  "$(for o in --root --worktrees --projects --brew-bin --prefix --lock; do grep -q -- "$o" "$README" && grep -q -- "$o" "$L/install.sh" || exit 1; done; echo $?)"
verifier "README : 150 lignes au plus ($(wc -l < "$README" | tr -d ' '))" "$([ "$(wc -l < "$README")" -le 150 ]; echo $?)"
verifier "README : aucun chemin de machine" "$(! grep -qE '/Us''ers/|/ho''me/' "$README"; echo $?)"

echo
echo "$OK ok, $KO échec(s)"
[ "$KO" -eq 0 ]
