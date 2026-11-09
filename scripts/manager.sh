#!/usr/bin/env bash
# Maintient la session Remote Control du manageur en vie.
# Une session par « jour de travail » (de 07:30 à 07:30) :
#   - premier démarrage du jour : session neuve, qui commence par le bilan de la nuit ;
#   - relance (plantage, redémarrage du Mac) : reprise de la session du jour, même historique.
# Le modèle du manageur est MODELE_MANAGER (config.env).
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN
cd "$LAB"
mkdir -p "$LOGS"

MARQUEUR="$LAB/.manager-session"      # contient : <jour> <uuid de la session>
PROMPT_MATIN="Nouvelle journée. Lis memory/lab/lab-Agent-Knowledge.md puis applique la skill morning-review, étapes 1 à 4 seulement : résumé ultra court, puis la liste numérotée des décisions à prendre et à revoir (nouveaux rapports + sections du haut de memory/<projet>/<projet>-Decisions.md). S'il n'y a rien de nouveau, dis-le en une ligne."

while true; do
  # Jour de travail décalé de 7 h 30 : un redémarrage à 01:00 reprend la session de la veille.
  JOUR=$(date -v-7H -v-30M +%F)
  NOM="Manager · $(date -v-7H -v-30M +%d/%m)"
  JOUR_MARQUEUR=""; SESSION=""
  [ -f "$MARQUEUR" ] && read -r JOUR_MARQUEUR SESSION < "$MARQUEUR"

  # caffeinate -i : le Mac ne s'endort pas tant que le manageur tourne
  if [ "$JOUR_MARQUEUR" = "$JOUR" ] && [ -n "$SESSION" ]; then
    caffeinate -i claude --model "$MODELE_MANAGER" --resume "$SESSION" --remote-control "$NOM"
  else
    SESSION=$(uuidgen | tr 'A-Z' 'a-z')
    echo "$JOUR $SESSION" > "$MARQUEUR"
    echo "$(date) : nouvelle session $NOM ($SESSION)" >> "$LOGS/manager.log"
    caffeinate -i claude --model "$MODELE_MANAGER" --session-id "$SESSION" --remote-control "$NOM" "$PROMPT_MATIN"
  fi
  echo "Manager arrêté le $(date), relance dans 30 s" >> "$LOGS/manager.log"
  sleep 30
done
