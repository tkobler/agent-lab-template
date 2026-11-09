#!/usr/bin/env bash
# Démarre le round « maintenant » (job launchd) puis attend sa fin et affiche le rapport.
# Le manageur le lance en arrière-plan : il est réveillé quand la commande se termine.
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
SIGNAL="$LAB/.now-running"

[ -f "$SIGNAL" ] && { echo "Un round « maintenant » tourne déjà."; exit 1; }
launchctl kickstart "gui/$(id -u)/$PREFIXE_LAUNCHAGENT.now" || { echo "Lancement impossible (job non chargé ?)"; exit 1; }

for _ in $(seq 1 30); do [ -f "$SIGNAL" ] && break; sleep 2; done
if [ ! -f "$SIGNAL" ]; then
  echo "Le round n'a pas démarré : un autre round occupe probablement la machine."
  tail -n 5 "$LOGS/launchd-now.log" 2>/dev/null
  exit 1
fi
read -r JOUR ID < "$SIGNAL"
echo "Round $ID démarré à $(date +%H:%M)."
while [ -f "$SIGNAL" ]; do sleep 30; done

RAPPORTS=$(ls "$JOUR"/"$ID"-*.md 2>/dev/null)
if [ -z "$RAPPORTS" ]; then
  echo "Round terminé sans rapport : config/NOW.md ne contenait aucune tâche ?"
else
  for r in $RAPPORTS; do echo "=== $r"; head -n 12 "$r"; done
fi
