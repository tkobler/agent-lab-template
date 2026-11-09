#!/usr/bin/env bash
# Usage : prepare-worktree.sh <projet> <branche claude/...> <dossier-du-worktree>
# Prépare un worktree du projet sur une branche claude/* : création, ou reprise à jour.
set -euo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
source "$ICI/read-project-config.sh"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

PROJET="${1:?projet manquant}"; BRANCHE="${2:?branche manquante}"; WT="${3:?dossier manquant}"
stop() { echo "ERREUR : $1"; exit 1; }

[[ "$BRANCHE" == claude/* ]] || stop "Branche « $BRANCHE » refusée : elle doit commencer par claude/."
git check-ref-format --branch "$BRANCHE" >/dev/null 2>&1 || stop "Nom de branche invalide : $BRANCHE"
[ -f "$LAB/config/projects/$PROJET.env" ] || stop "Projet inconnu : $PROJET (config/projects/$PROJET.env absent)."
lire_fiche "$LAB/config/projects/$PROJET.env"
[ -d "$REPO_PATH/.git" ] || stop "Dépôt introuvable : $REPO_PATH"

bash "$LAB/scripts/install-hooks.sh" "$REPO_PATH"
git -C "$REPO_PATH" fetch origin --prune || stop "git fetch a échoué (accès au dépôt distant ? gh auth status)"

if [ ! -d "$WT" ]; then
  git -C "$REPO_PATH" worktree add --detach "$WT" "origin/$BRANCHE_BASE" || stop "Création du worktree impossible"
fi
cd "$WT"
if [ -n "$(git status --porcelain)" ]; then
  git stash push -u -m "auto-stash du $(date '+%F %H:%M')"
  echo "Modifications non commitées mises de côté (git stash)."
fi

if git show-ref --verify --quiet "refs/heads/$BRANCHE"; then
  AMONT=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$BRANCHE")
  if [ -n "$AMONT" ] && ! git show-ref --verify --quiet "refs/remotes/$AMONT"; then
    stop "La branche $BRANCHE a disparu du dépôt distant (déjà mergée ou supprimée) : choisis un nouveau nom."
  fi
  git switch "$BRANCHE" || stop "Impossible de passer sur $BRANCHE (déjà ouverte dans une autre copie ?)"
  if [ -n "$AMONT" ]; then
    git merge --ff-only "$AMONT" || stop "$BRANCHE a divergé du dépôt distant : à régler à la main."
  fi
elif git show-ref --verify --quiet "refs/remotes/origin/$BRANCHE"; then
  git switch -c "$BRANCHE" --track "origin/$BRANCHE" || stop "Impossible de récupérer $BRANCHE"
else
  # --no-track : la branche ne doit pas suivre la base (elle suivra origin/claude/... après le premier push)
  git switch --no-track -c "$BRANCHE" "origin/$BRANCHE_BASE" || stop "Impossible de créer $BRANCHE"
fi
[ "$(git branch --show-current)" = "$BRANCHE" ] || stop "Pas sur la bonne branche, arrêt."
echo "Worktree prêt : $WT sur $BRANCHE"
