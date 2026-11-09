#!/usr/bin/env bash
# Usage : export-lab.sh <dossier-sortie> [--source D]
# Génère le LAB publiable (la structure du dépôt agent-lab, sans aucune donnée personnelle) dans <dossier-sortie>.
#   - copie une LISTE BLANCHE explicite (ci-dessous) depuis la source (défaut : le dépôt qui contient ce script) ;
#     tout ce qui n'y figure pas est ignoré : en particulier memory/, config/, reports/, logs/, projects/, worktrees/ ;
#     dans agents/, les sous-dossiers agents/<projet>/ (agents propres à un projet) ne sont jamais copiés ;
#   - refuse les liens symboliques et ignore .DS_Store ; ne copie jamais .git ;
#   - lance tests/controle-donnees-perso.sh sur la sortie et s'arrête en erreur s'il échoue : dans ce cas rien n'est
#     laissé dans <dossier-sortie> ;
#   - <dossier-sortie> doit être absent ou vide (jamais d'écrasement) et hors de la source.
# Ne publie rien : aucun git push, aucun dépôt créé, aucun appel réseau. La publication reste une action manuelle.
# Code de sortie : 0 = lab généré et contrôle vert, 1 = erreur ou contrôle rouge, 2 = mauvais usage.
set -euo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- LISTE BLANCHE (tout le reste est exclu) -------------------------------------------------------------------
DOSSIERS=(scripts agents prompts templates claude tests)          # copiés en entier (moins .DS_Store)
FICHIERS=(install.sh README.md CLAUDE.md config.example.env .gitignore)   # les deux derniers sont lus par install.sh
# tools/ : liste explicite, fichier par fichier. Livrés : agent_knowledge.py (généralisé : projets déduits du coffre
# memory/, aucun nom ni chemin en dur) + son test sur coffres factices ; test_agents_round.py (teste scripts/agents_round.py,
# livré) ; __init__.py (pour « python3 -m unittest » et « unittest tools.test_agent_knowledge »).
# Exclus (le contrôle anti-données perso les refuse) : test_agent_knowledge_coffre.py (pages réelles du coffre privé) ;
# controle_coffre.py, migrer_decisions.py et leurs tests (migration du coffre actuel, identifiants réels) ;
# test_depot.py (teste le vrai coffre memory/). Un outil devient publiable en l'ajoutant ici APRÈS l'avoir généralisé.
OUTILS=(tools/__init__.py tools/agent_knowledge.py tools/test_agent_knowledge.py tools/test_agents_round.py)
# ---------------------------------------------------------------------------------------------------------------

usage() { echo "Usage : export-lab.sh <dossier-sortie> [--source D]" >&2; exit 2; }
[ $# -ge 1 ] || usage
SORTIE_ARG="$1"; shift
SOURCE="$(dirname "$ICI")"
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="${2:?valeur manquante}"; shift 2 ;;
    *) usage ;;
  esac
done
[ -d "$SOURCE" ] || { echo "ERREUR : source introuvable : $SOURCE" >&2; exit 1; }
SOURCE="$(cd "$SOURCE" && pwd)"

# Sortie : absente ou vide, hors de la source.
PARENT="$(dirname "$SORTIE_ARG")"
[ -d "$PARENT" ] || { echo "ERREUR : le dossier parent de la sortie n'existe pas : $PARENT" >&2; exit 1; }
SORTIE="$(cd "$PARENT" && pwd)/$(basename "$SORTIE_ARG")"
case "$SORTIE/" in "$SOURCE"/*) echo "ERREUR : la sortie ne peut pas être dans la source." >&2; exit 1 ;; esac
if [ -e "$SORTIE" ]; then
  [ -d "$SORTIE" ] || { echo "ERREUR : la sortie existe et n'est pas un dossier : $SORTIE" >&2; exit 1; }
  [ -z "$(ls -A "$SORTIE")" ] || { echo "ERREUR : la sortie n'est pas vide (aucun écrasement) : $SORTIE" >&2; exit 1; }
fi

# Assemblage dans un dossier temporaire voisin ; déplacé vers la sortie seulement si le contrôle est vert.
STAGE="$(mktemp -d "$(dirname "$SORTIE")/.export-lab.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

for d in "${DOSSIERS[@]}"; do
  [ -d "$SOURCE/$d" ] || { echo "ERREUR : dossier de la liste blanche absent de la source : $d" >&2; exit 1; }
  mkdir -p "$STAGE/$d"
  cp -R "$SOURCE/$d/." "$STAGE/$d/"
done
for f in "${FICHIERS[@]}" ${OUTILS[@]+"${OUTILS[@]}"}; do
  [ -f "$SOURCE/$f" ] || { echo "ERREUR : fichier de la liste blanche absent de la source : $f" >&2; exit 1; }
  mkdir -p "$STAGE/$(dirname "$f")"
  cp "$SOURCE/$f" "$STAGE/$f"
done
# agents/<projet>/ : agents propres à un projet, jamais exportés (seuls les agents généraux, agents/*.md, le sont)
find "$STAGE/agents" -mindepth 1 -type d -prune -exec rm -rf {} +
find "$STAGE" -name .DS_Store -type f -delete
LIENS="$(find "$STAGE" -type l)"
if [ -n "$LIENS" ]; then
  echo "ERREUR : lien symbolique dans la liste blanche (refusé) :" >&2
  echo "${LIENS#"$STAGE"/}" >&2
  exit 1
fi
chmod +x "$STAGE"/scripts/*.sh "$STAGE"/install.sh "$STAGE"/tests/*.sh

# Contrôle anti-données personnelles sur toute la sortie, avec la copie du contrôle livrée dans le lab
# (elle exclut ses propres fixtures de faux exemples, situées à côté d'elle) (il ne montre que fichier:ligne et catégorie).
echo "Contrôle anti-données personnelles sur le lab..."
if ! bash "$STAGE/tests/controle-donnees-perso.sh" "$STAGE"; then
  echo "ECHEC : le contrôle anti-données personnelles a échoué : lab NON généré, rien écrit dans $SORTIE." >&2
  exit 1
fi

mkdir -p "$SORTIE"
cp -R "$STAGE/." "$SORTIE/"
echo "Lab généré dans $SORTIE ($(find "$SORTIE" -type f | wc -l | tr -d ' ') fichiers). Rien n'est publié."
