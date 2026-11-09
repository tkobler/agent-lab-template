#!/usr/bin/env bash
# Enchaîne les rounds de nuit (lancé à PREMIER_DEPART par le LaunchAgent « night », seul déclencheur : pas de round
# de jour automatique). Rounds 1, 2, … dans l'ordre, sans plafond choisi (décision D2) : la chaîne s'arrête au
# premier « ## ROUND R » absent de config/TASKS.md (une section présente mais vide reste un « rien à faire » de night.sh).
# Seule limite, technique : 99 rounds (night.sh n'accepte que les rounds 1 à 99).
# Avant CHAQUE départ (premier essai d'un round ou reprise) : départ seulement dans la fenêtre de nuit, de
# PREMIER_DEPART le soir (config.env, défaut 23:00) à DERNIER_DEPART le lendemain matin (défaut 04:00, tolérance
# 5 min). launchd lance la tâche au réveil si le Mac dormait à l'heure prévue : hors fenêtre, la chaîne ne fait rien.
# L'attente du verrou est bornée à la fin de la fenêtre. Limite de session (« You've hit your session limit · resets 4am ») : attente
# de la remise à zéro, puis REPRISE du même round. Limite hebdomadaire (« You've hit your weekly limit ») : si la
# remise est une heure seule (« resets 1am ») au plus tard à DERNIER_DEPART cette nuit, même attente et REPRISE
# (REPRISE_MOTIF=hebdo : night.sh corrige son rapport et son prompt) ; sinon (heure illisible, jour ou date, après
# DERNIER_DEPART, ou ESSAIS_MAX atteint) arrêt net de la nuit, ni reprise ni round suivant. Dernière tentative
# (ESSAIS_MAX) coupée par une limite de session : attente de la remise (si elle tombe avant le dernier départ,
# sinon fin de la nuit), puis round suivant.
# Durée max TIMEOUT_ROUND atteinte (« claude a terminé (code 124) ») avec des tâches non terminées (rapport absent ou
# minimal, section « Tâches non terminées » absente ou autre que « aucune ») : RELANCE immédiate du même round (même
# projet et branche, REPRISE_MOTIF=timeout), sous le même plafond ESSAIS_MAX et la même fenêtre : jamais de départ
# après DERNIER_DEPART (arrêt de la nuit comme pour les autres reprises).
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

DERNIER_DEPART="${DERNIER_DEPART-04:00}"
PREMIER_DEPART="${PREMIER_DEPART-23:00}"
ROUND_MAX=99                                   # limite technique : night.sh accepte les rounds 1 à 99
ESSAIS_MAX=4                                   # tentatives max par round
MARGE_DEPART=300                               # 5 min : une remise « resets 4am » (+2 min) part encore à 04:02
LOCK="${VERROU_ROUND:-/tmp/agent-lab-round.lock}"
NUIT=$(date -v-12H +%F)                        # même « date de nuit » que night.sh
mkdir -p "$LOGS"
exec >>"$LOGS/$NUIT-night-chain.log" 2>&1
RE_MATIN='^(0[0-9]|1[01]):[0-5][0-9]$'          # 00:00 à 11:59 : le lendemain matin de NUIT
RE_SOIR='^(1[2-9]|2[0-3]):[0-5][0-9]$'           # 12:00 à 23:59 : le soir de NUIT
if ! [[ "$DERNIER_DEPART" =~ $RE_MATIN ]]; then
  echo "DERNIER_DEPART « $DERNIER_DEPART » invalide (HH:MM entre 00:00 et 11:59 attendu) : 04:00 utilisé."
  DERNIER_DEPART="04:00"
fi
if ! [[ "$PREMIER_DEPART" =~ $RE_SOIR ]]; then
  echo "PREMIER_DEPART « $PREMIER_DEPART » invalide (HH:MM entre 12:00 et 23:59 attendu) : 23:00 utilisé."
  PREMIER_DEPART="23:00"
fi
DEBUT=$(date -j -f "%F %H:%M:%S" "$NUIT $PREMIER_DEPART:00" +%s)
LIMITE=$(date -j -v+1d -f "%F %H:%M:%S" "$NUIT $DERNIER_DEPART:00" +%s)
echo "=== Chaîne de nuit — $(date) — départs du $(date -r "$DEBUT" '+%d/%m %H:%M') au $(date -r "$LIMITE" '+%d/%m %H:%M') ==="

terminer() { echo "$1"; echo "=== Fin de la chaîne — $(date) ==="; exit 0; }

# hors_fenetre <tolérance en s> : « avant » (avant PREMIER_DEPART), « apres » (après DERNIER_DEPART + MARGE_DEPART
# + tolérance) ou rien si le départ est permis.
hors_fenetre() {
  local now; now=$(date +%s)
  if [ "$now" -lt "$DEBUT" ]; then echo avant
  elif [ "$now" -gt $((LIMITE + MARGE_DEPART + ${1:-0})) ]; then echo apres
  fi
}

taille() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }

# section_presente <R> : config/TASKS.md a une ligne « ## ROUND R » (hors commentaires HTML, espaces de fin ignorés),
# lue comme night.sh lit sa section.
section_presente() {
  [ -f "$LAB/config/TASKS.md" ] || return 1
  awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$LAB/config/TASKS.md" \
    | awk -v r="## ROUND $1" '/^## /{sub(/[[:space:]]+$/,""); if ($0==r) t=1} END{exit !t}'
}

# limite_tentative <journal du round> : limite rencontrée par la DERNIÈRE tentative. Même lecture que
# annoter_arret (night.sh, correctif motif-arret) : dernier bloc « === Round », jusqu'à « claude a terminé
# (code N) » ; une limite seulement si N est non nul et si le message est en début de ligne (un agent qui le
# cite ne compte pas). Affiche « hebdo|<resets …> », « session|<resets …> » ou rien. Hebdomadaire d'abord ; sa
# remise est lue sur la ligne hebdomadaire seule, en entier jusqu'à « ( » (« resets Oct 20, 6am »).
limite_tentative() {
  local log="$1" sortie code resets ligne
  [ -f "$log" ] || return 0
  sortie=$(awk 'BEGIN{f=1} /^=== Round /{b=""; f=1} /^claude a terminé/{f=0} f{b=b $0 "\n"} END{printf "%s", b}' "$log")
  code=$(awk '/^=== Round /{c=""} /^claude a terminé \(code /{c=$0} END{print c}' "$log" \
    | sed -n 's/^claude a terminé (code \([0-9][0-9]*\)).*/\1/p')
  [ -n "$code" ] && [ "$code" != 0 ] || return 0
  if grep -qE '^(Error: )?You.{1,3}ve hit your weekly limit' <<<"$sortie"; then
    ligne=$(grep -E '^(Error: )?You.{1,3}ve hit your weekly limit' <<<"$sortie" | tail -n 1)
    resets=$(grep -oE 'resets [^(]*' <<<"$ligne" | head -n 1) || resets=""
    resets="${resets%"${resets##*[![:space:]]}"}"   # espaces et CR de fin retirés
    echo "hebdo|$resets"
  elif grep -qE '^(Error: )?You.{1,3}ve hit your session limit' <<<"$sortie"; then
    resets=$(grep -oE 'resets [0-9]{1,2}(:[0-9]{2})?[ap]m' <<<"$sortie" | tail -n 1) || resets=""
    echo "session|$resets"
  fi
  return 0
}

# coupe_par_timeout <journal du round> <rapport(s) du round, motif glob> : la DERNIÈRE tentative a été coupée par
# TIMEOUT_ROUND (« claude a terminé (code 124) », écrit par night.sh) ET il reste des tâches. Code 0 = relancer.
# Tâches restantes sauf si le rapport a une section « ## Tâches non terminées » dont le contenu est « aucune » :
# rapport absent, vide, minimal (« Aucun rapport écrit »), section absente ou remplie = restantes (dans le doute, on relance).
coupe_par_timeout() {
  local log="$1" code rapport="" f contenu
  [ -f "$log" ] || return 1
  code=$(awk '/^=== Round /{c=""} /^claude a terminé \(code /{c=$0} END{print c}' "$log" \
    | sed -n 's/^claude a terminé (code \([0-9][0-9]*\)).*/\1/p')
  [ "$code" = 124 ] || return 1
  for f in $2; do [ -s "$f" ] && [ ! -L "$f" ] && { rapport="$f"; break; }; done
  [ -n "$rapport" ] || return 0
  grep -q '^Aucun rapport écrit' "$rapport" && return 0
  grep -q '^## Tâches non terminées' "$rapport" || return 0
  contenu=$(awk '/^## /{s=($0 ~ /^## Tâches non terminées/); next} s' "$rapport" \
    | tr -d '*_`.[:space:]' | tr 'A-Z' 'a-z')
  # « aucune », « - aucune », mais aussi la phrase « Aucune tâche non terminée » / « Aucune tâche restante »
  case "$contenu" in
    aucune|aucun|-aucune|-aucun|aucunetâchenonterminée|aucunetâcherestante|-aucunetâchenonterminée|-aucunetâcherestante) return 1 ;;
  esac
  return 0
}

# remise_epoch <« resets 4am » | « 12:10am » | vide> : heure (epoch) de la remise à zéro, la prochaine à venir ;
# heure absente ou illisible : réessai dans 30 min.
remise_epoch() {
  local t="${1#resets }" re='^[0-9]{1,2}(:[0-9]{2})?[ap]m$' ampm hm h m ts now
  now=$(date +%s)
  if ! [[ "$t" =~ $re ]]; then echo $((now + 1800)); return 0; fi
  ampm=${t: -2}; hm=${t%??}; h=${hm%%:*}; m=0
  [[ "$hm" == *:* ]] && m=${hm#*:}
  h=$((10#$h)); m=$((10#$m))
  [ "$ampm" = am ] && [ "$h" -eq 12 ] && h=0
  [ "$ampm" = pm ] && [ "$h" -ne 12 ] && h=$((h + 12))
  ts=$(date -j -f "%F %H:%M:%S" "$(date +%F) $h:$m:00" +%s)
  # Lendemain à la même heure murale (-v+1d, et non +86400 s : juste en cas de changement d'heure)
  [ "$ts" -le "$now" ] && ts=$(date -j -v+1d -f "%F %H:%M:%S" "$(date +%F) $h:$m:00" +%s)
  echo "$ts"
}

# reprise_hebdo_epoch <« resets 1am »…> : après une limite hebdomadaire, heure (epoch) de la remise si elle permet
# une reprise cette nuit : heure seule et lisible (« resets 1am », « resets 12:30am » ; ni jour, ni date) et au plus
# tard DERNIER_DEPART (LIMITE). Sinon rien : arrêt net.
reprise_hebdo_epoch() {
  local re='^resets (1[0-2]|[1-9])(:[0-5][0-9])?[ap]m$' ts
  [[ "${1:-}" =~ $re ]] || return 0
  ts=$(remise_epoch "$1")
  if [ -n "$ts" ] && [ "$ts" -le "$LIMITE" ]; then echo "$ts"; fi
  return 0
}

R=1
while [ "$R" -le "$ROUND_MAX" ]; do
  if ! section_presente "$R"; then
    echo "Pas de section « ## ROUND $R » dans config/TASKS.md : pas de départ, fin des rounds."; break
  fi
  essai=1; MOTIF=""                            # MOTIF : limite de la tentative précédente (session|hebdo), pour la REPRISE
  while :; do
    TOL=0
    [ "$essai" -gt 1 ] && TOL=60                # reprise décidée avant l'attente : un réveil en retard de < 1 min ne compte pas
    case "$(hors_fenetre "$TOL")" in
      avant) terminer "Avant le premier départ ($PREMIER_DEPART) : round $R non lancé (chaîne lancée hors de la fenêtre de nuit, par exemple au réveil du Mac) ; la prochaine nuit partira à l'heure." ;;
      apres) terminer "Dernier départ ($DERNIER_DEPART) dépassé : round $R (tentative $essai) non lancé, plus aucun départ cette nuit." ;;
    esac
    # Attente du verrou bornée à la fin de la fenêtre (jamais plus de 7200 s, comme avant).
    ATTENTE=$((LIMITE + MARGE_DEPART + TOL - $(date +%s)))
    [ "$ATTENTE" -gt 7200 ] && ATTENTE=7200
    [ "$ATTENTE" -lt 1 ] && ATTENTE=1
    JOURNAL_R="$LOGS/$NUIT-round-$R.log"
    AVANT=$(taille "$JOURNAL_R")
    echo "--- Round $R, tentative $essai — $(date)"
    if [ "$essai" -eq 1 ]; then
      flock -w "$ATTENTE" "$LOCK" "$LAB/scripts/night.sh" "$R"
    else
      REPRISE=1 REPRISE_MOTIF="$MOTIF" flock -w "$ATTENTE" "$LOCK" "$LAB/scripts/night.sh" "$R"
    fi
    # night.sh écrit toujours dans son journal ; journal inchangé = night.sh pas lancé (verrou non obtenu à temps).
    if [ "$(taille "$JOURNAL_R")" = "$AVANT" ]; then
      terminer "Round $R : verrou $LOCK non obtenu en $ATTENTE s (fin de la fenêtre : $DERNIER_DEPART + 5 min) ou night.sh arrêté avant son journal : round non lancé, plus aucun départ cette nuit."
    fi
    LIM=$(limite_tentative "$LOGS/$NUIT-round-$R.log")
    case "$LIM" in
      hebdo\|*)
        RESETS="${LIM#hebdo|}"
        TS=$(reprise_hebdo_epoch "$RESETS")
        if [ -z "$TS" ]; then
          terminer "Round $R : LIMITE HEBDOMADAIRE atteinte${RESETS:+ ($RESETS)} : remise illisible, avec un jour ou une date, ou après le dernier départ ($DERNIER_DEPART). Arrêt net de la nuit : aucune reprise, aucun round suivant."
        fi
        # Plus de tentative pour ce round : arrêt net (le round suivant buterait sur la même limite hebdomadaire).
        if [ "$essai" -ge "$ESSAIS_MAX" ]; then
          terminer "Trop de tentatives pour le round $R ($ESSAIS_MAX), la dernière coupée par la limite hebdomadaire (remise à $(date -r "$TS" '+%H:%M')). Arrêt net de la nuit : aucune reprise, aucun round suivant."
        fi
        MOTIF=hebdo
        echo "Round $R : limite hebdomadaire, remise à $(date -r "$TS" '+%H:%M') (au plus tard au dernier départ, $DERNIER_DEPART) : reprise comme pour une limite de session." ;;
      session\|*)
        TS=$(remise_epoch "${LIM#session|}")
        MOTIF=session
        echo "Round $R : limite de session, remise à $(date -r "$TS" '+%H:%M')." ;;
      *)
        # Durée max TIMEOUT_ROUND atteinte avec des tâches restantes : relance immédiate (pas de remise à zéro à
        # attendre), même projet, même branche (night.sh les relit dans TASKS.md). Même plafond ESSAIS_MAX ; la
        # fenêtre est revérifiée en tête de boucle (jamais de départ après DERNIER_DEPART).
        if coupe_par_timeout "$JOURNAL_R" "$LAB/reports/$NUIT/round-$R-*.md"; then
          if [ "$essai" -ge "$ESSAIS_MAX" ]; then
            echo "Round $R : durée max atteinte à la tentative $essai (ESSAIS_MAX=$ESSAIS_MAX) : plus de relance, round suivant."; break
          fi
          MOTIF=timeout; essai=$((essai + 1))
          echo "Round $R : durée max (TIMEOUT_ROUND) atteinte avec des tâches non terminées : relance (tentative $essai) si le dernier départ ($DERNIER_DEPART) le permet."
          continue
        fi
        echo "Round $R terminé sans limite de session."; break ;;
    esac
    DEPART=$((TS + 120))                        # 2 min de marge après la remise à zéro
    if [ "$DEPART" -gt $((LIMITE + MARGE_DEPART)) ]; then
      terminer "Remise après le dernier départ ($DERNIER_DEPART) : on s'arrête là pour la nuit."
    fi
    # Dernière tentative coupée par une limite de session (D3 B) : plus de reprise, mais on attend quand même la remise
    # à zéro (elle tombe avant le dernier départ : voir le test ci-dessus) avant le round suivant, qui buterait sinon
    # sur la même limite.
    DERNIERE=0; [ "$essai" -ge "$ESSAIS_MAX" ] && DERNIERE=1
    [ "$DERNIERE" = 1 ] && echo "Trop de tentatives pour le round $R ($ESSAIS_MAX) : plus de reprise ; attente de la remise à zéro avant le round suivant."
    echo "Attente jusqu'à $(date -r "$DEPART" '+%H:%M')…"
    caffeinate -i sleep $((DEPART - $(date +%s) > 0 ? DEPART - $(date +%s) : 0))
    [ "$DERNIERE" = 1 ] && break
    essai=$((essai + 1))
  done
  R=$((R + 1))
done
if [ "$R" -gt "$ROUND_MAX" ] && section_presente "$R"; then
  echo "Limite technique de $ROUND_MAX rounds atteinte : « ## ROUND $R » et suivants non lancés (night.sh accepte les rounds 1 à $ROUND_MAX)."
fi
echo "=== Fin de la chaîne — $(date) ==="
