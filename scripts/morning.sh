#!/usr/bin/env bash
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin"

NUIT=$(date -v-12H +%F)          # même « date de nuit » que night.sh
# Si un round (départ jusqu'à DERNIER_DEPART, 3 h 30 max) tourne encore, on attend sa fin (1 h max).
flock -w 3600 "${VERROU_ROUND:-/tmp/agent-lab-round.lock}" true || echo "morning.sh : round encore en cours après 1 h d'attente"
rm -f "$LAB/.night-running"

# Remise à zéro : les tâches de la nuit sont archivées dans reports/$NUIT/tasks-night.md
if [ -f "$LAB/reports/$NUIT/tasks-night.md" ]; then
  cp "$LAB/templates/TASKS.empty.md" "$LAB/config/TASKS.md"
fi

# Sauvegarde de la mémoire, de la config et des rapports sur GitHub. Seulement depuis la branche main, et seulement
# memory/ config/ reports/ : jamais de code (scripts/, agents/, tests/…), ni commité ni poussé par ce script.
# Sur toute autre branche (claude/*, tête détachée) : ni commit ni push.
DONNEES=(memory config reports)
sauvegarder_donnees() {
  cd "$LAB" || return 0
  local branche
  branche="$(git symbolic-ref --short -q HEAD || true)"
  if [ "$branche" != main ]; then
    echo "morning.sh : branche « ${branche:-tête détachée} » (pas main) : ni commit ni push."
    return 0
  fi
  local d
  for d in "${DONNEES[@]}"; do
    [ -e "$d" ] && { git add -A -- "$d" 2>/dev/null || true; }
  done
  if ! git diff --cached --quiet -- "${DONNEES[@]}" 2>/dev/null; then
    git commit -qm "nuit du $NUIT" -- "${DONNEES[@]}" || { echo "morning.sh : commit échoué."; return 0; }
  fi
  # Garde-fou : si des commits locaux non poussés touchent autre chose que les données, on ne pousse rien.
  git fetch -q origin main 2>/dev/null || { echo "morning.sh : fetch origin impossible : pas de push."; return 0; }
  local hors
  hors="$(git diff --name-only origin/main...HEAD -- . ':(exclude)memory' ':(exclude)config' ':(exclude)reports' 2>/dev/null)"
  if [ -n "$hors" ]; then
    echo "morning.sh : des commits locaux touchent du code (pas de push) :"; echo "$hors"
    return 0
  fi
  git push -q origin main || echo "morning.sh : push échoué (origin/main)."
}
sauvegarder_donnees

# Rotation du manageur : on ferme la session d'hier ; manager.sh voit un nouveau jour
# et démarre une session neuve qui écrit le bilan de la nuit.
tmux kill-session -t manager 2>/dev/null
launchctl kickstart -k "gui/$(id -u)/$PREFIXE_LAUNCHAGENT.manager"
