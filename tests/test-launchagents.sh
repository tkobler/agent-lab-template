#!/usr/bin/env bash
# Teste les modèles de LaunchAgents (templates/*.plist.template) : les 5 agents du lab (night, morning, morning-retry, manager,
# now) sont rendus par install.sh dans <LAB>/launchagents/<préfixe>.<nom>.plist, valides, sans marqueur, sans
# donnée de cette machine, et rien n'est installé ni chargé (HOME de substitution intact).
# Référence facultative : 1er argument ou LAUNCHAGENTS_REFERENCE=<dossier contenant les com.<préfixe>.<nom>.plist du lab réel>
# (lecture seule). Chaque plist rendu doit alors être équivalent (mêmes clés et valeurs) au plist réel, une fois les
# chemins du lab réel et du dossier Homebrew réels remplacés par ceux du faux lab.
# Usage : test-launchagents.sh [dossier de référence]        Code de sortie : 0 = tout passe. Nécessite macOS (plutil).
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (plutil)."; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-launchagents.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0; SKIP=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
source "$ICI/anciens-noms.sh"      # anciens noms français, assemblés (comparaison au lab réel)
NOMS="night morning morning-retry manager now"
REF="${1:-${LAUNCHAGENTS_REFERENCE:-}}"

echo "== les modèles de LaunchAgents (templates/)"
for n in $NOMS; do
  verifier "modèle $n.plist.template présent" "$([ -f "$SQ/templates/$n.plist.template" ]; echo $?)"
done
verifier "pas d'autre modèle de LaunchAgent que ces 5" "$([ "$(ls "$SQ"/templates/*.plist.template | wc -l | tr -d ' ')" -eq 5 ]; echo $?)"
verifier "plus aucun ancien modèle *.$AN_PLIST_MODELE" "$([ -z "$(ls "$SQ"/templates/*."$AN_PLIST_MODELE" 2>/dev/null)" ]; echo $?)"

echo "== installation dans un faux lab (HOME de substitution)"
FH="$TMP/home"; mkdir -p "$FH"
LAB="$TMP/racine/lab"; BREW="$TMP/brew/bin"; PFX="org.exemple"
SORTIE="$(HOME="$FH" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin "$BREW" --prefix "$PFX" 2>&1)"; CODE=$?
verifier "install.sh : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "annonce 5 modèles rendus, non chargés" "$(grep -q '5 modèle(s) de LaunchAgent rendu(s)' <<<"$SORTIE" && grep -q 'non chargés' <<<"$SORTIE"; echo $?)"
verifier "aucun SKIP ni ATTENTION" "$(! grep -qE 'SKIP|ATTENTION' <<<"$SORTIE"; echo $?)"
verifier "exactement 5 plist dans launchagents/" "$([ "$(ls "$LAB/launchagents" | wc -l | tr -d ' ')" -eq 5 ]; echo $?)"
for n in $NOMS; do
  P="$LAB/launchagents/$PFX.$n.plist"
  verifier "$n : plist présent" "$([ -f "$P" ]; echo $?)"
  verifier "$n : plutil -lint" "$(plutil -lint "$P" >/dev/null 2>&1; echo $?)"
  verifier "$n : aucun marqueur restant" "$(! grep -q '@[A-Z_]*@' "$P"; echo $?)"
  verifier "$n : étiquette = préfixe.$n" "$([ "$(plutil -extract Label raw "$P" 2>/dev/null)" = "$PFX.$n" ]; echo $?)"
  verifier "$n : journal launchd dans data/logs du LAB" "$([ "$(plutil -extract StandardOutPath raw "$P" 2>/dev/null)" = "$LAB/data/logs/launchd-$n.log" ] && [ "$(plutil -extract StandardErrorPath raw "$P" 2>/dev/null)" = "$LAB/data/logs/launchd-$n.log" ]; echo $?)"
done
verifier "night : lance scripts/night-chain.sh, tous les jours à 23:00" \
  "$([ "$(plutil -extract ProgramArguments.0 raw "$LAB/launchagents/$PFX.night.plist")" = "$LAB/scripts/night-chain.sh" ] \
     && [ "$(plutil -extract StartCalendarInterval.Hour raw "$LAB/launchagents/$PFX.night.plist")" = 23 ] \
     && [ "$(plutil -extract StartCalendarInterval.Minute raw "$LAB/launchagents/$PFX.night.plist")" = 0 ]; echo $?)"
verifier "morning : scripts/morning.sh à 07:30" \
  "$([ "$(plutil -extract ProgramArguments.0 raw "$LAB/launchagents/$PFX.morning.plist")" = "$LAB/scripts/morning.sh" ] \
     && [ "$(plutil -extract StartCalendarInterval.Hour raw "$LAB/launchagents/$PFX.morning.plist")" = 7 ] \
     && [ "$(plutil -extract StartCalendarInterval.Minute raw "$LAB/launchagents/$PFX.morning.plist")" = 30 ]; echo $?)"
verifier "manager : tmux du dossier Homebrew, session « manager », scripts/manager.sh, au chargement" \
  "$(P="$LAB/launchagents/$PFX.manager.plist"; [ "$(plutil -extract ProgramArguments.0 raw "$P")" = "$BREW/tmux" ] \
     && [ "$(plutil -extract ProgramArguments.4 raw "$P")" = manager ] && [ "$(plutil -extract ProgramArguments.5 raw "$P")" = "$LAB/scripts/manager.sh" ] \
     && [ "$(plutil -extract RunAtLoad raw "$P")" = true ] && [ "$(plutil -extract AbandonProcessGroup raw "$P")" = true ]; echo $?)"
verifier "now : flock -n sur le verrou, puis scripts/night.sh now ; pas d'horaire" \
  "$(P="$LAB/launchagents/$PFX.now.plist"; [ "$(plutil -extract ProgramArguments.0 raw "$P")" = "$BREW/flock" ] \
     && [ "$(plutil -extract ProgramArguments.1 raw "$P")" = -n ] && [ "$(plutil -extract ProgramArguments.2 raw "$P")" = /tmp/agent-lab-round.lock ] \
     && [ "$(plutil -extract ProgramArguments.3 raw "$P")" = "$LAB/scripts/night.sh" ] && [ "$(plutil -extract ProgramArguments.4 raw "$P")" = now ] \
     && ! plutil -extract StartCalendarInterval raw "$P" >/dev/null 2>&1; echo $?)"
verifier "morning-retry : 9:05, 10:05 et 11:05" \
  "$(P="$LAB/launchagents/$PFX.morning-retry.plist"; [ "$(plutil -extract StartCalendarInterval raw "$P")" = 3 ] \
     && [ "$(plutil -extract StartCalendarInterval.0.Hour raw "$P")" = 9 ] && [ "$(plutil -extract StartCalendarInterval.1.Hour raw "$P")" = 10 ] \
     && [ "$(plutil -extract StartCalendarInterval.2.Hour raw "$P")" = 11 ] && [ "$(plutil -extract StartCalendarInterval.2.Minute raw "$P")" = 5 ]; echo $?)"
verifier "le verrou du plist now = VERROU_ROUND par défaut de config.env (même valeur)" \
  "$(grep -q '^VERROU_ROUND="/tmp/agent-lab-round.lock"' "$LAB/config.env" && [ "$(plutil -extract ProgramArguments.2 raw "$LAB/launchagents/$PFX.now.plist")" = /tmp/agent-lab-round.lock ]; echo $?)"
verifier "le plist now ne porte plus de verrou écrit en dur dans le modèle (marqueur @VERROU_ROUND@)" \
  "$(grep -q '@VERROU_ROUND@' "$SQ/templates/now.plist.template" && ! grep -q '/tmp/agent-lab-round.lock' "$SQ/templates/now.plist.template"; echo $?)"
verifier "config.example.env : VERROU_ROUND en marqueur (@VERROU_ROUND@)" "$(grep -q '^VERROU_ROUND="@VERROU_ROUND@"' "$SQ/config.example.env"; echo $?)"
verifier "rien installé ni chargé : HOME de substitution vide" "$([ -z "$(ls -A "$FH")" ]; echo $?)"

echo "== deuxième préfixe et réinstallation"
HOME="$FH" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin "$BREW" --prefix "org.autre" >/dev/null 2>&1; CODE=$?
verifier "réinstallation avec un autre préfixe : code 0, nouveaux plist écrits" \
  "$([ "$CODE" -eq 0 ] && [ -f "$LAB/launchagents/org.autre.night.plist" ] && [ "$(plutil -extract Label raw "$LAB/launchagents/org.autre.night.plist")" = org.autre.night ]; echo $?)"

echo "== verrou réglable : valeur NON par défaut rendue dans config.env ET dans le plist now (décision D2 A)"
FH3="$TMP/home3"; mkdir -p "$FH3"; LAB3="$TMP/racine3/lab"; LOCK3="$TMP/verrous/round-test.lock"
SORTIE="$(HOME="$FH3" bash "$ICI/install-en-place.sh" "$TMP/racine5/lab" --brew-bin "$BREW" --lock "$LOCK3" 2>&1)"; CODE=$?
verifier "dossier du verrou inexistant : code 0 mais ATTENTION (flock n'y créerait rien)" "$([ "$CODE" -eq 0 ] && grep -q 'ATTENTION.*dossier du verrou' <<<"$SORTIE"; echo $?)"
mkdir -p "$TMP/verrous"
SORTIE="$(HOME="$FH3" bash "$ICI/install-en-place.sh" "$LAB3" --brew-bin "$BREW" --prefix org.verrou --lock "$LOCK3" 2>&1)"; CODE=$?
verifier "install.sh --lock : code 0, sans ATTENTION" "$([ "$CODE" -eq 0 ] && ! grep -q ATTENTION <<<"$SORTIE"; echo $?)"
verifier "config.env : VERROU_ROUND = valeur donnée" "$(grep -q "^VERROU_ROUND=\"$LOCK3\"" "$LAB3/config.env"; echo $?)"
P3="$LAB3/launchagents/org.verrou.now.plist"
verifier "plist now : flock -n sur la valeur donnée (et non /tmp/agent-lab-round.lock)" \
  "$([ "$(plutil -extract ProgramArguments.2 raw "$P3")" = "$LOCK3" ] && ! grep -q '/tmp/agent-lab-round.lock' "$P3"; echo $?)"
verifier "plist now valide, sans marqueur" "$(plutil -lint "$P3" >/dev/null 2>&1 && ! grep -q '@[A-Z_]*@' "$P3"; echo $?)"
verifier "les autres plist ne portent pas le verrou" "$(! grep -q "$LOCK3" "$LAB3/launchagents/org.verrou.night.plist"; echo $?)"
# Les scripts lisent le même réglage : night-chain.sh et morning.sh utilisent VERROU_ROUND de config.env
verifier "night-chain.sh et morning.sh lisent VERROU_ROUND (même verrou que le plist)" \
  "$(grep -q 'VERROU_ROUND' "$LAB3/scripts/night-chain.sh" && grep -q 'VERROU_ROUND' "$LAB3/scripts/morning.sh"; echo $?)"
# Réinstallation SANS --lock : config.env existant fait foi, le plist reprend sa valeur (pas de verrou différent)
HOME="$FH3" bash "$ICI/install-en-place.sh" "$LAB3" --brew-bin "$BREW" --prefix org.verrou >/dev/null 2>&1; CODE=$?
verifier "réinstallation sans --lock : le plist reprend le VERROU_ROUND de config.env" \
  "$([ "$CODE" -eq 0 ] && [ "$(plutil -extract ProgramArguments.2 raw "$P3")" = "$LOCK3" ]; echo $?)"
# Réinstallation avec un autre --lock : config.env (jamais écrasé) garde l'ancien : avertissement, pas de silence
SORTIE="$(HOME="$FH3" bash "$ICI/install-en-place.sh" "$LAB3" --brew-bin "$BREW" --prefix org.verrou --lock "$TMP/verrous/autre.lock" 2>&1)"; CODE=$?
verifier "autre --lock alors que config.env existe : code 0 et ATTENTION (valeurs différentes)" \
  "$([ "$CODE" -eq 0 ] && grep -q 'ATTENTION.*VERROU_ROUND' <<<"$SORTIE"; echo $?)"
# Valeurs refusées (l'arobase est construit à part : le contrôle anti-données perso le prendrait pour une adresse e-mail)
ARO="$(printf '\100')"
for v in 'verrou-relatif.lock' '/tmp/a"b.lock' '/tmp/a<b.lock' '/tmp/a&b.lock' "/tmp/a'b.lock" '/tmp/a$b.lock' "/tmp/a${ARO}b.lock" ''; do
  HOME="$FH3" bash "$ICI/install-en-place.sh" "$TMP/racine4/lab" --brew-bin "$BREW" --lock "$v" >/dev/null 2>&1; CODE=$?
  verifier "--lock « $v » refusé : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
done
verifier "rien créé pour les valeurs refusées" "$([ ! -e "$TMP/racine4/lab/config.env" ]; echo $?)"
verifier "rien installé ni chargé : HOME de substitution n° 3 vide" "$([ -z "$(ls -A "$FH3")" ]; echo $?)"

echo "== comparaison avec les LaunchAgents du lab réel"
if [ -n "$REF" ] && [ -d "$REF" ]; then
  # Un plist de référence par agent, sous son ANCIEN nom français : <préfixe réel>.<ancien nom>.plist ; les chemins réels
  # sont déduits du plist du premier agent (night). Les anciens noms sont ramenés aux nouveaux (table de tests/anciens-noms.sh) avant comparaison.
  ANCIENS="$AN_NUIT1 $AN_MATIN $AN_RELANCE_MATIN manager $AN_NOW"      # même ordre que NOMS
  PFXREEL="" ; LABREEL=""; BREWREEL=""
  for f in "$REF"/*."$AN_NUIT1".plist; do PFXREEL="$(basename "$f" ."$AN_NUIT1".plist)"; done
  LABREEL="$(plutil -extract ProgramArguments.0 raw "$REF/$PFXREEL.$AN_NUIT1.plist" 2>/dev/null | sed "s#/scripts/${AN_NUIT_CHAINE_SH}\$##")"
  BREWREEL="$(plutil -extract ProgramArguments.0 raw "$REF/$PFXREEL.manager.plist" 2>/dev/null | sed 's#/tmux$##')"
  verifier "chemins réels déduits des plist de référence" "$([ -n "$PFXREEL" ] && [ -n "$LABREEL" ] && [ -n "$BREWREEL" ]; echo $?)"
  # Réinstallation avec le préfixe réel pour comparer des plist de même nom
  HOME="$FH" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin "$BREW" --prefix "$PFXREEL" >/dev/null 2>&1
  set -- $ANCIENS
  for n in $NOMS; do
    ancien="$1"; shift
    python3 -I - "$REF/$PFXREEL.$ancien.plist" "$LAB/launchagents/$PFXREEL.$n.plist" "$LABREEL" "$LAB" "$BREWREEL" "$BREW" "$RENOMMAGES_PLIST" "$AN_NOW" <<'PY'
import plistlib, sys
ref, rendu, lab_r, lab_n, brew_r, brew_n, table, ancien_now = sys.argv[1:]
# Ancien nom -> nouveau nom (tests/anciens-noms.sh : table de correspondance), les plus longs d'abord ; une paire « ancien|nouveau » par ligne.
RENOMMAGES = [tuple(l.split("|", 1)) for l in table.splitlines() if l]
def remplacer(v):
    if isinstance(v, str):
        v = v.replace(lab_r, lab_n).replace(brew_r, brew_n)
        for a, n in RENOMMAGES:
            v = v.replace(a, n)
        return "now" if v == ancien_now else v
    if isinstance(v, list):
        return [remplacer(x) for x in v]
    if isinstance(v, dict):
        return {k: remplacer(x) for k, x in v.items()}
    return v
a = remplacer(plistlib.load(open(ref, "rb")))
b = plistlib.load(open(rendu, "rb"))
sys.exit(0 if a == b else 1)
PY
    verifier "$n : équivalent au LaunchAgent réel $ancien (mêmes clés et valeurs, noms et chemins ramenés au faux lab)" "$?"
  done
else
  SKIP=$((SKIP + 1)); echo "  SKIP comparaison au lab réel : dossier de référence non fourni (LAUNCHAGENTS_REFERENCE ou 1er argument)"
fi

echo "Résultat : $OK réussi(s), $KO échec(s), $SKIP ignoré(s)"
[ "$KO" -eq 0 ]
