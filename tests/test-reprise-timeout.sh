#!/usr/bin/env bash
# Teste night.sh REPRISE=1 REPRISE_MOTIF=timeout (relance d'un round coupé par TIMEOUT_ROUND, posée par night-chain.sh) :
# le prompt de reprise parle de la limite de temps (et non de limite de session / remise à zéro), garde le texte
# des tâches, et un rapport existant n'est pas supprimé alors que le rapport minimal « Aucun rapport écrit » l'est.
# Vrai night.sh dans un faux lab temporaire, claude / caffeinate / gtimeout doublés dans le HOME de substitution :
# aucun vrai claude, aucun push. Nécessite macOS (date -v). Usage : test-reprise-timeout.sh   Code 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans night.sh)."; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/reprise-timeout.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME/.local/bin"
RACINE="$TMP/racine"; LAB="$RACINE/lab"
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
dans_faux_home() { HOME="$FAUXHOME" "$@"; }

dans_faux_home bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
verifier "faux lab installé" "$([ -x "$LAB/scripts/night.sh" ]; echo $?)"
printf '\nPUSH_BRANCHES="non"\nOUVRIR_PR="non"\n' >> "$LAB/config.env"
git init -q --bare -b main "$RACINE/origine.git"
git clone -q "$RACINE/origine.git" "$RACINE/projets/demo" 2>/dev/null
git -C "$RACINE/projets/demo" -c user.name=Essai -c user.email=essai@exemple.com commit -q --allow-empty -m init
git -C "$RACINE/projets/demo" push -q origin main 2>/dev/null
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$RACINE/projets/demo" > "$LAB/config/projects/demo.env"
printf '## ROUND 1\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Tâche de nuit\n' > "$LAB/config/TASKS.md"

printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/caffeinate"
printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/gtimeout"
# claude doublé : note le prompt reçu (argument après -p) et si le rapport existait au lancement
printf '%s\n' '#!/bin/bash' \
  '[ "$1" = -p ] && printf %s "$2" > "$SORTIES_ESSAI/prompt.txt"' \
  'if [ -e "$RAPPORT_ESSAI" ]; then echo oui > "$SORTIES_ESSAI/rapport-vu.txt"; else echo non > "$SORTIES_ESSAI/rapport-vu.txt"; fi' \
  'exit 0' > "$FAUXHOME/.local/bin/claude"
chmod +x "$FAUXHOME/.local/bin/"*
NUIT="$(date -v-12H +%F)"
export SORTIES_ESSAI="$TMP" RAPPORT_ESSAI="$LAB/reports/$NUIT/round-1-demo.md"
mkdir -p "$LAB/reports/$NUIT"

lancer() {  # <motif ou vide> : night.sh 1 en reprise
  rm -f "$TMP/prompt.txt" "$TMP/rapport-vu.txt"
  REPRISE=1 REPRISE_MOTIF="$1" dans_faux_home bash "$LAB/scripts/night.sh" 1 > "$TMP/sortie.txt" 2>&1
}

echo "== reprise après durée max (REPRISE_MOTIF=timeout)"
printf 'STATUT: partiel\nARRÊT : durée max atteinte (TIMEOUT_ROUND=1m, code 124) à 01:00\n\n# Round 1\nTravail fait.\n' > "$RAPPORT_ESSAI"
lancer timeout
verifier "claude lancé avec un prompt" "$([ -s "$TMP/prompt.txt" ]; echo $?)"
verifier "prompt : REPRISE, limite de temps (TIMEOUT_ROUND), reprise tout de suite" "$(grep -q '^REPRISE : ce round a été coupé par la limite de temps du round (TIMEOUT_ROUND), il reprend tout de suite' "$TMP/prompt.txt"; echo $?)"
verifier "prompt : ni « limite de session » ni « remise à zéro »" "$(! grep -qE 'limite de session|remise à zéro' "$TMP/prompt.txt"; echo $?)"
verifier "prompt : le texte des tâches est conservé" "$(grep -q 'Tâche de nuit' "$TMP/prompt.txt"; echo $?)"
verifier "rapport réel conservé pour la reprise" "$([ "$(cat "$TMP/rapport-vu.txt")" = oui ]; echo $?)"

echo "== reprise après durée max, rapport minimal : supprimé avant la reprise"
printf 'STATUT: echec\nARRÊT : durée max atteinte (TIMEOUT_ROUND=1m, code 124) à 01:00\n\n# Round 1\n\nAucun rapport écrit (code de sortie 124). Voir logs/x.log\n' > "$RAPPORT_ESSAI"
lancer timeout
verifier "rapport minimal supprimé au lancement de claude" "$([ "$(cat "$TMP/rapport-vu.txt")" = non ]; echo $?)"

echo "== non-régression : limite de session inchangée"
printf 'STATUT: partiel\n\n# Round 1\n' > "$RAPPORT_ESSAI"
lancer session
verifier "prompt : « limite de session » et « remise à zéro » toujours là" "$(grep -q '^REPRISE : ce round a été coupé par la limite de session, il reprend après la remise à zéro' "$TMP/prompt.txt"; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
