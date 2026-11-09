#!/usr/bin/env bash
# Usage : install-hooks.sh <chemin-du-dépôt>
# Interdit les commits sur main/master et tout push hors des branches claude/*.
# Idempotent : night.sh et direct-session.sh le relancent à chaque fois, car un `npm install`
# avec husky (ou équivalent) peut changer core.hooksPath. Les hooks du projet restent appelés.
set -euo pipefail
REPO="${1:?Usage : install-hooks.sh <chemin-du-dépôt>}"
cd "$REPO"
COMMUN="$(cd "$(git rev-parse --git-common-dir)" && pwd)"   # partagé par tous les worktrees
HOOKS="$COMMUN/hooks-agent-lab"   # un dépôt déjà équipé garde l'ancien dossier de hooks : il reste appelé via .suivant (sans boucle)

SUIVANT=$(git config --get core.hooksPath || true)
[ "$SUIVANT" = "$HOOKS" ] && SUIVANT=$(cat "$HOOKS/.suivant" 2>/dev/null || true)
[ -n "$SUIVANT" ] || SUIVANT="$COMMUN/hooks"                  # hooks classiques du dépôt
mkdir -p "$HOOKS"
printf '%s\n' "$SUIVANT" > "$HOOKS/.suivant"

cat > "$HOOKS/pre-commit" <<'EOF'
#!/bin/sh
b=$(git branch --show-current)
case "$b" in
  main|master) echo "⛔ Commit interdit sur $b (garde-fou Claude lab)"; exit 1 ;;
esac
n="$(cat "$(dirname "$0")/.suivant")/pre-commit"
[ -x "$n" ] && exec "$n" "$@"
exit 0
EOF

cat > "$HOOKS/pre-push" <<'EOF'
#!/bin/sh
entree=$(cat)
echo "$entree" | while read local_ref local_sha remote_ref remote_sha; do
  [ -z "$remote_ref" ] && continue
  case "$remote_ref" in
    refs/heads/claude/*) ;;
    *) echo "⛔ Push vers $remote_ref interdit (seules les branches claude/* sont autorisées)"; exit 1 ;;
  esac
done || exit 1
n="$(cat "$(dirname "$0")/.suivant")/pre-push"
[ -x "$n" ] && { echo "$entree" | "$n" "$@"; exit $?; }
exit 0
EOF

chmod +x "$HOOKS/pre-commit" "$HOOKS/pre-push"
git config core.hooksPath "$HOOKS"
echo "Garde-fous actifs ($HOOKS)"
