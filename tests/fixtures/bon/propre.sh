#!/usr/bin/env bash
# FIXTURE PROPRE : doit passer le contrôle (marqueurs, exemples et chemins relatifs seulement).
LAB="@LAB@"
WORKTREES="@WORKTREES@"
source "$LAB/config.env"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin"
# Contact d'exemple : alice@exemple.com ; dépôt d'exemple : https://github.com/exemple/depot
GITHUB="exemple/depot"
# Jeton : à lire dans le trousseau, jamais ici. Le mot password sans valeur affectée ne compte pas.
