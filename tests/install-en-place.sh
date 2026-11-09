#!/usr/bin/env bash
# Aide des tests (pas un test) : fabrique un « clone » du dépôt dans <LAB>, puis lance install.sh EN PLACE.
# Usage : install-en-place.sh <LAB> [options de install.sh]
#   - <LAB> absent ou vide : y copie les fichiers du dépôt source (suivis par git ou non ignorés, donc l'état courant,
#     modifications non commitées comprises), fait un « git init » et un commit de base ; <LAB> devient le lab ;
#   - <LAB> déjà installé (install.sh présent) : réinstallation en place, rien n'est recopié ;
#   - SANS_INSTALL=1 : s'arrête après la fabrication du dépôt (pas d'installation) ;
#   - COPIER_DONNEES=1 : copie aussi memory/, config/ et reports/ (sinon lab neuf, voir plus bas) ;
#   - source : la variable SOURCE_DEPOT (défaut : le dépôt qui contient ce script ; sans .git : tous les fichiers).
# Le code de sortie est celui d'install.sh. HOME, brew et le reste viennent de l'environnement de l'appelant.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="${SOURCE_DEPOT:-$(dirname "$ICI")}"
LAB="${1:?Usage : install-en-place.sh <LAB> [options]}"; shift

if [ ! -f "$LAB/install.sh" ]; then
  mkdir -p "$LAB"
  [ -z "$(ls -A "$LAB")" ] || { echo "install-en-place.sh : $LAB n'est pas vide et n'est pas un lab." >&2; exit 1; }
  if [ -e "$SOURCE/.git" ]; then
    LISTE() { git -C "$SOURCE" ls-files -co --exclude-standard -z; }
  else
    LISTE() { (cd "$SOURCE" && find . -type f ! -path './.git/*' -print0); }
  fi
  while IFS= read -r -d '' f; do
    f="${f#./}"
    # Par défaut : un lab NEUF, comme celui qu'on crée depuis le template (export-lab.sh n'emporte ni memory/, ni config/,
    # ni reports/, ni tools/) : install.sh génère alors les gabarits. COPIER_DONNEES=1 : clone complet, données comprises.
    if [ "${COPIER_DONNEES:-0}" != 1 ]; then
      case "$f" in memory/*|config/*|reports/*|data/*|tools/*) continue ;; esac
    fi
    [ -f "$SOURCE/$f" ] || continue
    mkdir -p "$LAB/$(dirname "$f")"
    cp -p "$SOURCE/$f" "$LAB/$f"
  done < <(LISTE)
  # Les scripts sont suivis par git avec le droit d'exécution (100755) : on le rétablit si la source l'a perdu (copie sans les droits).
  chmod +x "$LAB"/install.sh "$LAB"/scripts/*.sh "$LAB"/tests/*.sh 2>/dev/null || true
  git -C "$LAB" init -q -b main
  git -C "$LAB" add -A
  git -C "$LAB" -c user.name=Essai -c user.email=essai@exemple.com commit -q -m "base du faux depot" || true
fi
[ "${SANS_INSTALL:-0}" != 1 ] || exit 0     # SANS_INSTALL=1 : seulement fabriquer le dépôt, sans lancer install.sh
exec bash "$LAB/install.sh" "$@"
