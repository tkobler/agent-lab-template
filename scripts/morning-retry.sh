#!/usr/bin/env bash
# Filet de sécurité du matin (09:05, 10:05, 11:05) : si la revue du matin n'a pas été faite
# (ex. quota épuisé par la nuit au moment de 07:30), on relance une session manageur neuve
# qui envoie le bilan comme d'habitude.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$LAB"
LOG="$LOGS/manager.log"

JOUR=$(date -v-7H -v-30M +%F)
DEBUT_JOUR=$(date -j -f "%F %H:%M:%S" "$JOUR 07:30:00" +%s)   # secondes explicites : sinon date -j prend celles de l'heure courante
REVUE=$(stat -f %m .review-done 2>/dev/null || echo 0)

# Revue déjà faite aujourd'hui : rien à faire.
[ "$REVUE" -ge "$DEBUT_JOUR" ] && exit 0
# Aucun nouveau rapport : la session du matin a juste dit « rien de nouveau ».
# Repère absent = revue jamais faite : tout rapport compte comme nouveau.
if [ -f .review-done ]; then
  NOUVEAU="$(find reports -name 'round-*.md' -newer .review-done 2>/dev/null | head -1)"
else
  NOUVEAU="$(find reports -name 'round-*.md' 2>/dev/null | head -1)"
fi
[ -z "$NOUVEAU" ] && exit 0

# L'utilisateur parle déjà au manageur (session écrite il y a moins de 15 min) : on ne coupe pas.
SESSION=""; [ -f .manager-session ] && read -r _ SESSION < .manager-session
TRANSCRIPT="$HOME/.claude/projects/$(echo "$LAB" | tr '/' '-')/$SESSION.jsonl"
if [ -n "$SESSION" ] && [ -f "$TRANSCRIPT" ] && \
   [ $(( $(date +%s) - $(stat -f %m "$TRANSCRIPT") )) -lt 900 ]; then
  echo "$(date) : morning-retry : revue pas faite mais session active, pas de relance" >> "$LOG"
  exit 0
fi

echo "$(date) : morning-retry : revue du matin absente, nouvelle session manageur" >> "$LOG"
rm -f .manager-session            # manager.sh repart sur une session neuve avec le prompt du matin
tmux kill-session -t manager 2>/dev/null
launchctl kickstart -k "gui/$(id -u)/$PREFIXE_LAUNCHAGENT.manager"
