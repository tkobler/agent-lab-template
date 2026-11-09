#!/usr/bin/env bash
# À inclure (source). Une commande est-elle couverte par les permissions d'un round ? Imite les règles Bash(...) de
# Claude Code : le motif est une glob sur la commande ENTIÈRE (« * » = n'importe quoi, tout autre caractère est
# littéral), un motif sans « * » est une égalité exacte, et un interdit l'emporte toujours sur un autorisé.
# Utilisé par night.sh (--check, vrai round, « fiches », --essai) pour la clé COMMANDES_TEST des fiches projets.
# Compatible bash 3.2 (macOS).
#   motif_couvre <argument du motif> <commande>        0 si le motif couvre la commande
#   commande_permise <commande> <autorisés> <interdits>  0 couverte ; 1 non couverte ; 2 interdite ; 3 composée
#   commandes_manquantes <cmd1|cmd2> <autorisés> <interdits>
#       affiche « PERMISSION MANQUANTE : <commande> » (puis la raison, indentée) pour chaque commande non permise ;
#       renvoie 1 s'il y en a au moins une. Les listes sont celles de night.sh (OUTILS, INTERDITS : motifs séparés par des virgules).

# Argument d'un motif Bash(...) : « git status* » -> couvre-t-il la commande ?
motif_couvre() {
  local m="$1" t="$2" p="" c i prefixe
  [ -n "$m" ] && [ -n "$t" ] || return 1
  # Ancienne forme « préfixe:* » : le préfixe seul, ou le préfixe suivi d'un espace et de la suite
  case "$m" in
    *:'*')
      prefixe="${m%:\*}"
      motif_couvre "$prefixe" "$t" && return 0
      motif_couvre "$prefixe *" "$t"; return $? ;;
  esac
  for ((i = 0; i < ${#m}; i++)); do
    c="${m:i:1}"
    case "$c" in '*') p+='*' ;; *) p+="\\$c" ;; esac
  done
  [[ "$t" == $p ]]
}

# Une commande contient-elle un enchaînement ou une redirection ? Claude Code évalue alors chaque morceau
# séparément : on ne le simule pas, la commande est signalée (déclarer une commande simple par entrée).
_commande_composee() {
  case "$1" in
    *'&'*|*';'*|*'|'*|*'<'*|*'>'*|*'`'*|*'$('*|*$'\n'*|*$'\r'*) return 0 ;;
  esac
  return 1
}

# Un des motifs Bash(...) de la liste (séparés par des virgules) couvre-t-il la commande ? « Bash » seul = tout.
_liste_couvre() {
  local liste="$1" t="$2" m arg motifs
  [ -n "$liste" ] || return 1
  IFS=, read -ra motifs <<<"$liste"
  for m in "${motifs[@]}"; do
    if [ "$m" = Bash ]; then return 0; fi
    if [[ "$m" =~ ^Bash\((.*)\)$ ]]; then
      arg="${BASH_REMATCH[1]}"
      motif_couvre "$arg" "$t" && return 0
    fi
  done
  return 1
}

commande_permise() {
  local t="$1" autorises="${2:-}" interdits="${3:-}"
  _commande_composee "$t" && return 3
  # L'interdit est testé en premier : il l'emporte même sur une commande non autorisée.
  _liste_couvre "$interdits" "$t" && return 2
  _liste_couvre "$autorises" "$t" && return 0
  return 1
}

commandes_manquantes() {
  local liste="${1:-}" autorises="${2:-}" interdits="${3:-}" cmd cmds manque=0 code
  [ -n "$liste" ] || return 0
  IFS='|' read -ra cmds <<<"$liste"
  for cmd in "${cmds[@]}"; do
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"; cmd="${cmd%"${cmd##*[![:space:]]}"}"     # espaces de bord retirés
    [ -n "$cmd" ] || continue
    code=0
    commande_permise "$cmd" "$autorises" "$interdits" || code=$?
    case "$code" in
      0) ;;
      1) echo "PERMISSION MANQUANTE : $cmd"; echo "  (non couverte par OUTILS / OUTILS_EXTRA : ajouter un motif Bash(...) à la fiche, avec un chemin relatif)"; manque=1 ;;
      2) echo "PERMISSION MANQUANTE : $cmd"; echo "  (bloquée par un interdit de night.sh ou INTERDITS_EXTRA : un interdit l'emporte)"; manque=1 ;;
      3) echo "PERMISSION MANQUANTE : $cmd"; echo "  (commande composée : &&, ;, |, redirection ou substitution ; déclarer une commande simple par entrée)"; manque=1 ;;
    esac
  done
  return "$manque"
}

# Nombre de commandes d'une liste « cmd1|cmd2 » (entrées vides ignorées)
compter_commandes() {
  local liste="${1:-}" cmd cmds n=0
  [ -n "$liste" ] || { echo 0; return 0; }
  IFS='|' read -ra cmds <<<"$liste"
  for cmd in "${cmds[@]}"; do
    [[ "$cmd" == *[![:space:]]* ]] && n=$((n + 1))
  done
  echo "$n"
}
