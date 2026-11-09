#!/usr/bin/env bash
# Recherche d'un agent par son tag (le « [tag] » d'une tâche).
#   agents/<tag>.md           : agent général (tous les projets)
#   agents/<projet>/<tag>.md  : agent spécifique au projet du round (le sous-dossier d'un autre projet n'est jamais lu)
# Le général gagne en cas de doublon : l'agent du projet est ignoré, avec un avertissement sur la sortie d'erreur.
# Usage CLI : resolve-agent.sh <dossier-agents> <projet|""> <tag>
#   affiche le chemin du fichier retenu. Code 0 = trouvé, 1 = introuvable (ou tag/projet invalide), 2 = mauvais usage.
# Usage bibliothèque : source resolve-agent.sh ; trouver_agent <dossier-agents> <projet|""> <tag>
# Un tag ou un projet qui n'est pas un simple nom (« / », « .. », caractères hors a-z A-Z 0-9 . _ -) est refusé :
# une tâche ne peut pas faire lire un fichier hors de agents/.

nom_simple() {
  local re='^[A-Za-z0-9][A-Za-z0-9._-]*$'
  [[ "${1:-}" =~ $re ]] && [[ "$1" != *..* ]]
}

# trouver_agent <dossier-agents> <projet|""> <tag> : chemin sur la sortie standard, code 1 si introuvable.
trouver_agent() {
  local dir="${1:-}" projet="${2:-}" tag="${3:-}" general projet_f=""
  nom_simple "$tag" || return 1
  [ -d "$dir" ] || return 1
  general="$dir/$tag.md"
  if [ -n "$projet" ] && nom_simple "$projet"; then projet_f="$dir/$projet/$tag.md"; fi
  if [ -f "$general" ]; then
    if [ -n "$projet_f" ] && [ -f "$projet_f" ]; then
      echo "ATTENTION : agents/$tag.md (général) et agents/$projet/$tag.md (projet) portent le même tag : le général est utilisé, celui du projet est ignoré." >&2
    fi
    printf '%s\n' "$general"
    return 0
  fi
  if [ -n "$projet_f" ] && [ -f "$projet_f" ]; then
    printf '%s\n' "$projet_f"
    return 0
  fi
  return 1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  if [ $# -ne 3 ]; then echo "Usage : resolve-agent.sh <dossier-agents> <projet|\"\"> <tag>" >&2; exit 2; fi
  trouver_agent "$1" "$2" "$3"
fi
