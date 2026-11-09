#!/usr/bin/env bash
# Teste night-chain.sh sans plafond de rounds (décision D2) : la chaîne enchaîne les rounds 1, 2, … jusqu'au premier
# « ## ROUND N » absent de config/TASKS.md, avec 99 comme seule limite technique (night.sh n'accepte que les rounds 1 à 99).
# Faux lab temporaire, HOME de substitution, night.sh REMPLACÉ par une doublure qui note son appel : aucun claude lancé.
# La fenêtre de nuit est ouverte toute la journée (PREMIER_DEPART=12:00, DERNIER_DEPART=11:59) pour que le test ne
# dépende pas de l'heure. Nécessite macOS (date -v) et flock (Homebrew) : sinon SKIP.
# Usage : test-chaine.sh        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans night-chain.sh)."; exit 0; fi
FLOCK="$(command -v flock || true)"
if [ -z "$FLOCK" ]; then echo "SKIP : flock (Homebrew) introuvable."; exit 0; fi
BREW="$(dirname "$FLOCK")"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-chaine.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FH="$TMP/home"; mkdir -p "$FH"
LAB="$TMP/racine/lab"
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }

HOME="$FH" bash "$ICI/install-en-place.sh" "$LAB" --brew-bin "$BREW" >/dev/null 2>&1
verifier "faux lab installé" "$([ -x "$LAB/scripts/night-chain.sh" ]; echo $?)"
# L'ancien plafond de rounds : son nom est assemblé ici pour qu'il n'apparaisse nulle part dans le dépôt (contrôle par grep)
ANCIENNE_CLE="MAX_""ROUNDS"
verifier "config.env sans l'ancien plafond de rounds" "$(! grep -q "$ANCIENNE_CLE" "$LAB/config.env"; echo $?)"
verifier "aucun fichier installé (lab entier, sauf logs) ne mentionne l'ancien plafond de rounds" "$(! grep -rq --exclude-dir=data --exclude-dir=.git --exclude=README.md "$ANCIENNE_CLE" "$LAB"; echo $?)"
# Doublure de night.sh : note l'appel et écrit dans le journal du round (la chaîne lit sa taille pour savoir qu'il a tourné).
# Sans scénario : round terminé (code 0). Avec $LAB/scenario-<R>.txt, une ligne par appel (la première est consommée) :
#   ok | coupe-restant (code 124, rapport avec tâches non terminées) | coupe-fini (code 124, « Tâches non terminées : aucune »)
#   | coupe-sans-rapport (code 124, aucun rapport) | coupe-tard (comme coupe-restant, mais l'horloge saute de 2 jours)
#   | coupe-contenu:<texte> (code 124, section « Tâches non terminées » = <texte>)
#   | coupe-puis-ok (le journal porte un code 124 PUIS un code 0 : seul le dernier compte, rapport avec tâches restantes)
#   | ok-puis-coupe (un code 0 PUIS un code 124 : le dernier compte)
#   | coupe-saut (comme coupe-restant, mais l'horloge saute à l'instant $SAUT_CIBLE, epoch)
cat > "$LAB/scripts/night.sh" <<'EOF'
#!/usr/bin/env bash
LAB="$(cd "$(dirname "$0")/.." && pwd)"
D=$(date -v-12H +%F)
J="$LAB/data/logs/$D-round-$1.log"
R="$LAB/reports/$D/round-$1-demo.md"
SC="$LAB/scenario-$1.txt"
s=ok
if [ -s "$SC" ]; then s=$(head -n 1 "$SC"); sed -i '' 1d "$SC"; fi
echo "$1" >> "$LAB/appels.txt"
echo "$1 reprise=${REPRISE:-0} motif=${REPRISE_MOTIF:-}" >> "$LAB/appels-env.txt"
echo "=== Round $1 (doublure) ===" >> "$J"
mkdir -p "$LAB/reports/$D"
rapport() { printf 'STATUT: partiel\nARRÊT : durée max atteinte (TIMEOUT_ROUND=1m, code 124) à 01:00\n\n# Round %s\n\n## Tâches non terminées\n%s\n\n## Pièges / à savoir\naucun\n' "$1" "$2" > "$R"; }
case "$s" in
  ok) echo "claude a terminé (code 0)" >> "$J" ;;
  coupe-restant) rapport "$1" "- Raison : manque de temps"; echo "claude a terminé (code 124)" >> "$J" ;;
  coupe-tard) rapport "$1" "- Raison : manque de temps"; echo 172800 > "$DECALAGE"; echo "claude a terminé (code 124)" >> "$J" ;;
  coupe-contenu:*) rapport "$1" "${s#coupe-contenu:}"; echo "claude a terminé (code 124)" >> "$J" ;;
  coupe-puis-ok) rapport "$1" "- Raison : manque de temps"; echo "claude a terminé (code 124)" >> "$J"; echo "claude a terminé (code 0)" >> "$J" ;;
  ok-puis-coupe) rapport "$1" "- Raison : manque de temps"; echo "claude a terminé (code 0)" >> "$J"; echo "claude a terminé (code 124)" >> "$J" ;;
  coupe-saut) rapport "$1" "- Raison : manque de temps"; echo $(( SAUT_CIBLE - $(command date +%s) )) > "$DECALAGE"; echo "claude a terminé (code 124)" >> "$J" ;;
  coupe-fini) rapport "$1" "aucune"; echo "claude a terminé (code 124)" >> "$J" ;;
  coupe-sans-rapport) echo "claude a terminé (code 124)" >> "$J" ;;
esac
EOF
chmod +x "$LAB/scripts/night.sh"
sed -i '' "s#^VERROU_ROUND=.*#VERROU_ROUND=\"$TMP/verrou.lock\"#; s#^PREMIER_DEPART=.*#PREMIER_DEPART=\"12:00\"#; s#^DERNIER_DEPART=.*#DERNIER_DEPART=\"11:59\"#" "$LAB/config.env"

taches() {  # <rounds présents, séparés par des espaces> : écrit config/TASKS.md avec ces sections
  { echo "# Tâches"; for r in "$@"; do printf '\n## ROUND %s\nprojet: demo\nbranche: claude/x\n\n- [codeur] tâche\n' "$r"; done; } > "$LAB/config/TASKS.md"
}
# Horloge truquée : « date +%s » (la comparaison des heures de night-chain.sh) ajoute le contenu de $DECALAGE ; une
# fonction exportée passe avant le PATH, que night-chain.sh redéfinit.
DECALAGE="$TMP/decalage.txt"; export DECALAGE
date() { if [ "$*" = "+%s" ]; then echo $(( $(command date +%s) + $(cat "$DECALAGE" 2>/dev/null || echo 0) )); else command date "$@"; fi; }
export -f date
scenario() {  # <round> <scénarios…> : un scénario par appel de la doublure
  local r="$1"; shift; printf '%s\n' "$@" > "$LAB/scenario-$r.txt"
}
lancer() {  # lance la chaîne (HOME de substitution) ; efface les traces précédentes
  rm -f "$LAB/appels.txt" "$LAB/appels-env.txt" "$LAB"/data/logs/* "$DECALAGE"; rm -rf "$LAB"/reports/*
  # DEPART_A=<epoch> : horloge truquée dès le départ, pour que « maintenant » vaille cet instant
  if [ -n "${DEPART_A:-}" ]; then echo $(( DEPART_A - $(command date +%s) )) > "$DECALAGE"; fi
  HOME="$FH" bash "$LAB/scripts/night-chain.sh" >/dev/null 2>&1
  rm -f "$LAB"/scenario-*.txt
}
appels() { if [ -f "$LAB/appels.txt" ]; then tr '\n' ' ' < "$LAB/appels.txt"; fi; }
journal() { cat "$LAB"/data/logs/*-night-chain.log 2>/dev/null; }

echo "== 5 rounds présents, le 6 absent, le 7 présent : plus que l'ancien plafond (3 ou 4), arrêt au premier absent"
taches 1 2 3 4 5 7
lancer
verifier "rounds lancés : 1 2 3 4 5, dans l'ordre" "$([ "$(appels)" = "1 2 3 4 5 " ]; echo $?)"
verifier "le round 7 (après le trou) n'est pas lancé" "$(! grep -qx 7 "$LAB/appels.txt"; echo $?)"
verifier "journal : « Pas de section ## ROUND 6 »" "$(journal | grep -q 'Pas de section « ## ROUND 6 »'; echo $?)"
verifier "verrou de config.env (valeur non défaut) réellement utilisé par la chaîne : fichier créé" "$([ -e "$TMP/verrou.lock" ]; echo $?)"
verifier "journal : plus de mention de plafond" "$(! journal | grep -qiE "plafond|$ANCIENNE_CLE"; echo $?)"

echo "== un ancien config.env qui contient encore l'ancien plafond (=2) est sans effet"
echo "${ANCIENNE_CLE}=2" >> "$LAB/config.env"
lancer
verifier "rounds lancés : 1 à 5 malgré l'ancien plafond =2" "$([ "$(appels)" = "1 2 3 4 5 " ]; echo $?)"
sed -i '' "/^${ANCIENNE_CLE}=/d" "$LAB/config.env"

echo "== cas limites"
taches
lancer
verifier "aucune section : aucun round lancé, message sur le round 1" "$([ -z "$(appels)" ] && journal | grep -q 'Pas de section « ## ROUND 1 »'; echo $?)"
rm -f "$LAB/config/TASKS.md"
lancer
verifier "config/TASKS.md absent : aucun round lancé, pas d'erreur" "$([ -z "$(appels)" ] && journal | grep -q 'Fin de la chaîne'; echo $?)"
taches 2 3
lancer
verifier "round 1 absent mais 2 et 3 présents : rien (la chaîne commence au round 1)" "$([ -z "$(appels)" ]; echo $?)"

echo "== limite technique : 99 rounds"
TOUS=(); for i in $(seq 1 100); do TOUS+=("$i"); done
taches "${TOUS[@]}"
lancer
verifier "99 rounds lancés, le 100e jamais (night.sh n'accepte que 1 à 99)" "$([ "$(wc -l < "$LAB/appels.txt" | tr -d ' ')" -eq 99 ] && ! grep -qx 100 "$LAB/appels.txt" && [ "$(tail -n 1 "$LAB/appels.txt")" = 99 ]; echo $?)"
verifier "journal : limite technique de 99 rounds signalée" "$(journal | grep -q 'Limite technique de 99 rounds'; echo $?)"
taches "${TOUS[@]:0:99}"
lancer
verifier "exactement 99 sections : 99 rounds, pas de message de limite" "$([ "$(wc -l < "$LAB/appels.txt" | tr -d ' ')" -eq 99 ] && ! journal | grep -q 'Limite technique'; echo $?)"

echo "== round coupé par TIMEOUT_ROUND (code 124) : relance du même round avant le suivant (décision du 20/10)"
taches 1 2
scenario 1 coupe-restant ok
lancer
verifier "coupé avec tâches restantes : round 1 relancé, puis round 2 (appels 1 1 2)" "$([ "$(appels)" = "1 1 2 " ]; echo $?)"
verifier "la relance porte REPRISE=1 et REPRISE_MOTIF=timeout, le premier appel non" "$([ "$(head -n 1 "$LAB/appels-env.txt")" = "1 reprise=0 motif=" ] && sed -n 2p "$LAB/appels-env.txt" | grep -qx '1 reprise=1 motif=timeout'; echo $?)"
verifier "journal : relance annoncée" "$(journal | grep -q 'Round 1 : durée max (TIMEOUT_ROUND) atteinte avec des tâches non terminées'; echo $?)"

taches 1 2
scenario 1 ok
lancer
verifier "round terminé (code 0) : pas de relance (appels 1 2)" "$([ "$(appels)" = "1 2 " ]; echo $?)"

taches 1 2
scenario 1 coupe-fini
lancer
verifier "coupé par le délai mais « Tâches non terminées : aucune » : pas de relance (appels 1 2)" "$([ "$(appels)" = "1 2 " ]; echo $?)"

taches 1 2
scenario 1 coupe-sans-rapport ok
lancer
verifier "coupé sans aucun rapport : relancé (appels 1 1 2)" "$([ "$(appels)" = "1 1 2 " ]; echo $?)"

taches 1 2
scenario 1 coupe-restant coupe-restant coupe-restant coupe-restant coupe-restant
lancer
verifier "toujours coupé : ESSAIS_MAX=4 appels pour le round 1, pas de boucle infinie, puis le round 2 (1 1 1 1 2)" "$([ "$(appels)" = "1 1 1 1 2 " ]; echo $?)"
verifier "journal : trop de tentatives signalé" "$(journal | grep -q 'Round 1 : durée max atteinte à la tentative 4 (ESSAIS_MAX=4)'; echo $?)"

taches 1 2
scenario 1 coupe-tard ok
lancer
verifier "coupé après le dernier départ (horloge +2 jours) : ni relance ni round 2 (appel 1 seul)" "$([ "$(appels)" = "1 " ]; echo $?)"
verifier "journal : dernier départ dépassé, round 1 tentative 2 non lancé" "$(journal | grep -q 'Dernier départ (11:59) dépassé : round 1 (tentative 2) non lancé'; echo $?)"

echo "== « Tâches non terminées » : variantes de « aucune » lues comme terminé, vraies tâches restantes relancées"
for contenu in "Aucune." "- Aucune" "**Aucune**" "Aucun" "aucune tâche non terminée" "Aucune tâche non terminée." "**Aucune tâche restante**"; do
  taches 1 2
  scenario 1 "coupe-contenu:$contenu" ok
  lancer
  verifier "« $contenu » : pas de relance (appels 1 2)" "$([ "$(appels)" = "1 2 " ]; echo $?)"
done
for contenu in "- Raison : manque de temps" "Aucune tâche n'est terminée" "Tâche 2 non terminée"; do
  taches 1 2
  scenario 1 "coupe-contenu:$contenu" ok
  lancer
  verifier "« $contenu » : relance (appels 1 1 2)" "$([ "$(appels)" = "1 1 2 " ]; echo $?)"
done

echo "== code 124 ancien suivi d'un code 0 : le dernier code compte"
taches 1 2
scenario 1 coupe-puis-ok
lancer
verifier "124 puis 0 dans le journal (rapport avec tâches restantes) : terminé, pas de relance (appels 1 2)" "$([ "$(appels)" = "1 2 " ]; echo $?)"
taches 1 2
scenario 1 ok-puis-coupe ok
lancer
verifier "0 puis 124 : coupé, relance (appels 1 1 2)" "$([ "$(appels)" = "1 1 2 " ]; echo $?)"
taches 1 2
scenario 1 coupe-restant ok
scenario 2 coupe-restant coupe-puis-ok
lancer
verifier "round 1 coupé puis ok ; round 2 coupé puis (124 puis 0) : appels 1 1 2 2" "$([ "$(appels)" = "1 1 2 2 " ]; echo $?)"

echo "== frontière DERNIER_DEPART (11:59) : marge de 5 min, tolérance de 60 s pour les reprises"
NUIT_T=$(command date -v-12H +%F)
LIM_T=$(command date -j -v+1d -f "%F %H:%M:%S" "$NUIT_T 11:59:00" +%s)
taches 1
DEPART_A=$((LIM_T + 300 - 15)) lancer
verifier "1er départ 15 s avant LIMITE+5 min : round 1 lancé" "$([ "$(appels)" = "1 " ]; echo $?)"
DEPART_A=$((LIM_T + 300 + 15)) lancer
verifier "1er départ 15 s après LIMITE+5 min : rien lancé" "$([ -z "$(appels)" ]; echo $?)"
verifier "journal : dernier départ dépassé, round 1 tentative 1" "$(journal | grep -q 'Dernier départ (11:59) dépassé : round 1 (tentative 1) non lancé'; echo $?)"
taches 1 2
export SAUT_CIBLE=$((LIM_T + 300 + 45))
scenario 1 coupe-saut ok
DEPART_A=$((LIM_T - 600)) lancer
verifier "reprise 45 s après LIMITE+5 min (tolérance 60 s) : round 1 relancé (appels 1 1)" "$([ "$(appels)" = "1 1 " ]; echo $?)"
verifier "…mais pas le round 2 (premier départ, tolérance 0)" "$(! grep -qx 2 "$LAB/appels.txt"; echo $?)"
export SAUT_CIBLE=$((LIM_T + 300 + 75))
scenario 1 coupe-saut ok
DEPART_A=$((LIM_T - 600)) lancer
verifier "reprise 75 s après LIMITE+5 min (hors tolérance) : pas de relance (appel 1 seul)" "$([ "$(appels)" = "1 " ]; echo $?)"
verifier "journal : dernier départ dépassé, round 1 tentative 2" "$(journal | grep -q 'Dernier départ (11:59) dépassé : round 1 (tentative 2) non lancé'; echo $?)"
unset SAUT_CIBLE

verifier "HOME de substitution intact" "$([ -z "$(ls -A "$FH")" ]; echo $?)"
echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
