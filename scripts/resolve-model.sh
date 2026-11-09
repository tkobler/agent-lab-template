#!/usr/bin/env bash
# Choix du cerveau (modèle) : réglage à trois niveaux, priorité agent > projet > lab.
#   agent  : champ « model: » de l'en-tête du fichier agents/<nom>.md (absent ou « inherit » = pas de choix)
#   projet : clé MODELE="..." de config/projects/<projet>.env (lue par read-project-config.sh)
#   lab    : MODELE_LAB de config.env (défaut de toute l'installation)
# Usage CLI : resolve-model.sh [--agent fichier.md] [--project valeur] [--lab valeur] [--source]
#   affiche le modèle retenu (avec --source : « modèle<tabulation>niveau », niveau = agent|projet|lab).
#   Sans --lab, le défaut du lab est $MODELE_LAB. Code 0 = modèle trouvé, 1 = aucun niveau n'en définit, 2 = mauvais usage.
# Usage bibliothèque : source resolve-model.sh ; resoudre_modele <agent.md|""> <projet|""> <lab|"">
# Une valeur qui ne ressemble pas à un nom de modèle (espace, $, ;, guillemet…) est ignorée avec un avertissement
# sur la sortie d'erreur, et le niveau suivant s'applique : une fiche modifiée ne peut pas injecter de commande.

modele_valide() {
  local re='^[A-Za-z0-9][]A-Za-z0-9._:/[-]*$'    # lettres, chiffres, . _ : / [ ] - (ex. « opus[1m] »)
  [[ "${1:-}" =~ $re ]]
}

# modele_agent <fichier.md> : valeur de « model: » dans l'en-tête (entre les deux premières lignes « --- »).
modele_agent() {
  local f="${1:-}" ligne v="" n=0
  [ -n "$f" ] && [ -f "$f" ] || return 0
  while IFS= read -r ligne || [ -n "$ligne" ]; do
    ligne="${ligne%$'\r'}"
    n=$((n + 1))
    if [ "$n" -eq 1 ]; then [ "$ligne" = "---" ] || return 0; continue; fi
    [ "$ligne" = "---" ] && break
    if [[ "$ligne" =~ ^model:[[:space:]]*(.*)$ ]]; then
      v="${BASH_REMATCH[1]}"
      v="${v%"${v##*[![:space:]]}"}"
      v="${v#[\"\']}"; v="${v%[\"\']}"
      break
    fi
  done < "$f"
  [ "$v" = inherit ] && v=""
  printf '%s' "$v"
}

# resoudre_modele_source <agent.md|""> <projet|""> <lab|""> : « modèle<tab>niveau », code 1 si aucun.
resoudre_modele_source() {
  local v niveau
  for niveau in agent projet lab; do
    case "$niveau" in
      agent) v="$(modele_agent "${1:-}")" ;;
      projet) v="${2:-}" ;;
      lab) v="${3:-}" ;;
    esac
    [ -n "$v" ] || continue
    if modele_valide "$v"; then printf '%s\t%s\n' "$v" "$niveau"; return 0; fi
    echo "ATTENTION : modèle « $v » ignoré au niveau $niveau (caractères non admis)" >&2
  done
  return 1
}

resoudre_modele() {
  local r; r="$(resoudre_modele_source "$@")" || return 1
  printf '%s\n' "${r%%$'\t'*}"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -uo pipefail
  AGENT=""; PROJET=""; LAB_MODELE="${MODELE_LAB:-}"; AVEC_SOURCE=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) AGENT="${2?valeur manquante}"; shift 2 ;;
      --project) PROJET="${2?valeur manquante}"; shift 2 ;;
      --lab) LAB_MODELE="${2?valeur manquante}"; shift 2 ;;
      --source) AVEC_SOURCE=1; shift ;;
      *) echo "Usage : resolve-model.sh [--agent fichier.md] [--project valeur] [--lab valeur] [--source]" >&2; exit 2 ;;
    esac
  done
  if [ "$AVEC_SOURCE" = 1 ]; then resoudre_modele_source "$AGENT" "$PROJET" "$LAB_MODELE"; exit $?; fi
  resoudre_modele "$AGENT" "$PROJET" "$LAB_MODELE"
fi
