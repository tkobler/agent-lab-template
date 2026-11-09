#!/usr/bin/env bash
# Usage : controle-donnees-perso.sh [dossier]
# Contrôle automatique « la partie publiable ne contient aucune donnée personnelle ni aucun chemin propre à ce Mac ».
# Sans argument : analyse la partie publiable du dépôt (dossier parent de tests/) : scripts/, agents/, prompts/,
# templates/, claude/, tests/, docs/, install.sh, config.example.env, README.md, CLAUDE.md, .gitignore.
# Dans agents/, seuls les agents généraux (agents/*.md) en font partie : les sous-dossiers agents/<projet>/ (agents
# propres à un projet, nommés d'après lui) sont ignorés sans argument.
# Les dossiers de données (memory/, config/, reports/, ...) ne sont PAS contrôlés : ils sont personnels par nature.
# Avec un argument : analyse tout ce dossier.
# Code de sortie : 0 = rien trouvé, 1 = au moins un problème, 2 = mauvais usage.
#
# Ce qui est cherché (motifs génériques, écrits avec des crochets pour ne pas se reconnaître eux-mêmes) :
#   CHEMIN-MAC   : dossiers personnels et racines de comptes (macOS, Linux, Windows), volumes montés, dossiers
#                  système privés, dossier de Homebrew et ses dépôts, chemins « maison » du lab actuel
#   COMPTE       : le nom du compte courant (id -un) dans un chemin ou une adresse, la valeur de $HOME,
#                  les adresses et identifiants de git config (lus à l'exécution)
#   EMAIL        : toute adresse e-mail (sauf domaines d'exemple), y compris celles en .local
#   JETON        : jetons GitHub/GitLab/OpenAI/Anthropic/Slack/AWS/npm/Google, jetons JWT et Bearer, clés privées
#   MOT-DE-PASSE : affectation (= ou :) d'un mot de passe, secret, jeton ou clé d'API à une valeur, majuscules ou non
#   GITHUB       : URL GitHub, GitLab ou Bitbucket avec un compte réel, et GITHUB="compte/dépôt" qui ne sont pas des exemples
#   NOM-PROJET   : noms de projets propres à une installation (ils ne doivent pas figurer dans le cœur) ;
#                  aussi les noms factices des fixtures mauvaises (projet, agent, script ou lab suivi du marqueur factice)
#   BINAIRE      : fichier binaire, non analysable : échec plutôt qu'un « OK » silencieux
# Les NOMS de fichiers sont analysés avec les mêmes motifs. Une erreur de grep (fichier illisible), ou aucun
# fichier à analyser, est un échec.
# Le nom du compte est cherché seulement dans un chemin ou une adresse : le mot seul n'est pas signalé,
# car le futur nom du lab peut coïncider avec lui.
# Le dossier tests/fixtures/ (faux exemples volontairement mauvais) est exclu quand on analyse un autre
# dossier ; on peut l'analyser en le passant en argument.
# La sortie donne fichier:ligne et la catégorie, jamais le contenu trouvé (pour ne rien recopier dans un journal).
set -uo pipefail

ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CIBLE="${1:-$(dirname "$ICI")}"
SANS_ARG=0; [ $# -ge 1 ] || SANS_ARG=1
if [ ! -d "$CIBLE" ]; then echo "Usage : controle-donnees-perso.sh [dossier]" >&2; exit 2; fi
CIBLE="$(cd "$CIBLE" && pwd)"
FIXTURES="$ICI/fixtures"
case "$CIBLE/" in "$FIXTURES"/*) FIXTURES="/dossier-inexistant-pour-ne-rien-exclure" ;; esac

TMPC="$(mktemp -d "${TMPDIR:-/tmp}/controle-perso.XXXXXX")"
trap 'rm -rf "$TMPC"' EXIT
RACINES=("$CIBLE")
EXCLUS_AGENTS=()
if [ "$SANS_ARG" -eq 1 ]; then      # partie publiable seulement
  RACINES=()
  # agents/<projet>/ (agents propres à un projet, jamais exportés) n'est pas la partie publiable : seuls les agents
  # généraux (agents/*.md) le sont. Passé en argument, un sous-dossier reste contrôlé.
  EXCLUS_AGENTS=(! -path "$CIBLE/agents/*/*")
  for e in scripts agents prompts templates claude tests docs install.sh config.example.env README.md CLAUDE.md .gitignore; do
    [ -e "$CIBLE/$e" ] && RACINES+=("$CIBLE/$e")
  done
  [ "${#RACINES[@]}" -gt 0 ] || RACINES=("$CIBLE/.aucune-partie-publiable")
fi
find "${RACINES[@]}" 2>/dev/null -type f ${EXCLUS_AGENTS[@]+"${EXCLUS_AGENTS[@]}"} ! -path '*/.git/*' ! -path "$FIXTURES/*" ! -name .DS_Store -print0 | sort -z > "$TMPC/liste"
FICHIERS=()
while IFS= read -r -d '' f; do FICHIERS+=("$f"); done < "$TMPC/liste"
NB_FICHIERS=${#FICHIERS[@]}
: > "$TMPC/noms"
for f in ${FICHIERS[@]+"${FICHIERS[@]}"}; do printf '%s\n' "${f#"$CIBLE"/}" >> "$TMPC/noms"; done

PROBLEMES=0
signaler_ligne() { echo "TROUVÉ $1 [$2]${3:+ $3}"; PROBLEMES=$((PROBLEMES + 1)); }

# chercher <catégorie> <regex d'exclusion sur « fichier:ligne:trouvé » ou vide> <options de grep...>
# Cherche dans le contenu de tous les fichiers puis dans leurs noms.
chercher() {
  local cat="$1" excl="$2" brut l; shift 2
  [ "$NB_FICHIERS" -gt 0 ] || return 0
  brut="$(grep -InHo "$@" -- "${FICHIERS[@]}" 2>"$TMPC/err")"; local rc=$?
  if [ "$rc" -ge 2 ]; then signaler_ligne "(grep)" "ERREUR" "code $rc, fichier illisible ? catégorie $cat"; fi
  if [ -n "$brut" ]; then
    [ -z "$excl" ] || brut="$(grep -viE "$excl" <<<"$brut")" || brut=""
    if [ -n "$brut" ]; then
      while IFS= read -r l; do signaler_ligne "${l#"$CIBLE"/}" "$cat"; done < <(cut -d: -f1,2 <<<"$brut" | sort -u)
    fi
  fi
  # Noms de fichiers : mêmes motifs
  brut="$(grep -no "$@" "$TMPC/noms" 2>/dev/null)" || brut=""
  if [ -n "$brut" ] && [ -n "$excl" ]; then brut="$(grep -viE "$excl" <<<"$brut")" || brut=""; fi
  if [ -n "$brut" ]; then
    while IFS= read -r l; do
      signaler_ligne "$(sed -n "${l}p" "$TMPC/noms")" "$cat" "(nom de fichier)"
    done < <(cut -d: -f1 <<<"$brut" | sort -u)
  fi
}

# --- Fichiers binaires : non analysables
for f in ${FICHIERS[@]+"${FICHIERS[@]}"}; do
  if [ -s "$f" ] && ! grep -Iq '' "$f" 2>/dev/null; then signaler_ligne "${f#"$CIBLE"/}" "BINAIRE" "(fichier binaire non analysable)"; fi
done

# --- Chemins propres à ce Mac ou à un compte
chercher CHEMIN-MAC "" -E \
  -e '/Us[e]rs(/|$)' \
  -e '[A-Za-z]:\\+Us[e]rs' \
  -e '/ho[m]e/[A-Za-z0-9_.-]+' \
  -e '/ro[o]t([/"'"'"'[:space:]]|$)' \
  -e '/Vol[u]mes/' \
  -e '/priv[a]te/(var|tmp|etc)' \
  -e '/usr/local/Ce[l]lar' \
  -e '/opt/h[o]mebrew' \
  -e '(\$HOME|\$\{HOME\}|~)/claude-hq' \
  -e '(\$HOME|\$\{HOME\}|~)/la[b]-factice'

# --- Compte courant, dossier personnel, identifiants de git config (valeurs lues à l'exécution)
NOM="$(id -un 2>/dev/null || true)"
if [[ "$NOM" =~ ^[A-Za-z0-9_-]{3,}$ ]]; then
  chercher COMPTE "" -E -e "/$NOM(/|\$)" -e "~$NOM(/|\$)" -e "(^|[^A-Za-z0-9_.-])$NOM@[A-Za-z]" -e "@$NOM([^A-Za-z0-9_-]|\$)"
fi
if [ "${#HOME}" -gt 4 ]; then chercher COMPTE "" -F -e "$HOME"; fi
for cle in user.email github.user; do
  for portee in "" "--global"; do
    # shellcheck disable=SC2086
    v="$(git config $portee --get "$cle" 2>/dev/null || true)"
    [ "${#v}" -ge 4 ] || continue
    chercher COMPTE "" -F -e "$v"
  done
done

# --- Adresses e-mail (domaines d'exemple exclus ; les marqueurs @NOM@ n'en sont pas)
chercher EMAIL '@(exemple|example)\.(com|org|net|fr)$|@[a-z0-9.-]+\.(invalid|test)$' -E \
  -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z]{2,}'

# --- Jetons et clés
chercher JETON "" -E \
  -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
  -e 'github_pat_[A-Za-z0-9_]{20,}' \
  -e 'glpat-[A-Za-z0-9_-]{16,}' \
  -e 'sk-[A-Za-z0-9_-]{20,}' \
  -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'npm_[A-Za-z0-9]{30,}' \
  -e 'AIza[0-9A-Za-z_-]{30,}' \
  -e 'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}' \
  -e 'Bearer[[:space:]]+[A-Za-z0-9._~+/=-]{16,}' \
  -e '-----BEGIN [A-Z ]*PRIVATE KEY-----'

# --- Mots de passe et secrets affectés (= ou :), casse ignorée
chercher MOT-DE-PASSE "" -iE \
  -e '(password|passwd|secret|token|api_?key)[A-Za-z_]*[[:space:]]*[=:][[:space:]]*["'"'"']?[^[:space:]"'"'"'$<{@]{6,}'
chercher MOT-DE-PASSE "" -iE \
  -e '(password|passwd)[[:space:]]*[=:][[:space:]]*["'"'"']?[^[:space:]"'"'"'$<{@]{4,}'

# --- Identifiant réel sur un hébergeur de dépôts (les exemples exemple/example/compte/OWNER sont admis)
chercher GITHUB '(github\.com|gitlab\.com|bitbucket\.org)[:/](exemple|example|compte|owner|votre|<)|GITHUB="(exemple|example|compte|owner|votre|<)' -E \
  -e '(github\.com|gitlab\.com|bitbucket\.org)[:/][A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' \
  -e 'GITHUB="[^"@]+/[^"]+"'

# --- Noms de projets propres à une installation
chercher NOM-PROJET "" -iE \
  -e 'glidat[o]r' \
  -e 'monke[y]c' \
  -e 'connect[i]q' \
  -e 'analyste-activit[e]' \
  -e 'relancer-simulat[e]ur' \
  -e 'export-notio[n]' \
  -e 'nuit[2]\.plist' \
  -e '(proje[t]|agen[t]|scrip[t]|la[b])-factice'

if [ "$NB_FICHIERS" -eq 0 ]; then
  echo "ÉCHEC : aucun fichier à analyser dans $CIBLE (un contrôle sans rien contrôler ne vaut pas « OK »)"
  exit 1
fi
if [ "$PROBLEMES" -gt 0 ]; then
  echo "ÉCHEC : $PROBLEMES problème(s) dans $NB_FICHIERS fichier(s) analysé(s) ($CIBLE)"
  exit 1
fi
echo "OK : $NB_FICHIERS fichier(s) analysé(s), aucune donnée personnelle ni chemin propre à ce Mac"
exit 0
