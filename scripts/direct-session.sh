#!/usr/bin/env bash
# Usage : direct-session.sh <projet> <branche claude/...>   ouvre une session de travail dans l'app Claude
#         direct-session.sh --close <projet>                 ferme cette session
set -euo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
unset ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN

if [ "${1:-}" = "--close" ]; then
  tmux kill-session -t "direct-${2:?projet manquant}" && echo "Session directe ${2} fermée."
  exit 0
fi
case "${1:-}" in --*) echo "Option inconnue : $1 (seule --close est acceptée)" >&2; exit 2 ;; esac
PROJET="${1:?Usage : direct-session.sh <projet> <branche claude/...>}"
BRANCHE="${2:?branche manquante}"
tmux has-session -t "direct-$PROJET" 2>/dev/null && { echo "Une session directe est déjà ouverte sur $PROJET."; exit 0; }

WT="$WORKTREES/$PROJET-direct"
bash "$LAB/scripts/prepare-worktree.sh" "$PROJET" "$BRANCHE" "$WT"
tmux new-session -d -s "direct-$PROJET" -c "$WT" \
  "caffeinate -i claude --remote-control 'Direct · $PROJET'"
echo "Session « Direct · $PROJET » ouverte sur $BRANCHE : elle apparaît dans l'app Claude."
