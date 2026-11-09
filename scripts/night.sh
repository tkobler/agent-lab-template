#!/usr/bin/env bash
# Usage : night.sh <N|now> [--check]
#   N (1 à 99) : round de nuit, tâches lues dans la section « ## ROUND N » de config/TASKS.md (relu à chaque round)
#   now        : round immédiat, tâches lues dans config/NOW.md (section « ## NOW »)
#   --check : analyse le fichier et affiche ce qui serait lancé, sans rien exécuter (ni claude, ni worktree,
#                ni écriture dans reports/ ou logs/).
#   fiches : contrôle à blanc de toutes les fiches config/projects/*.env (lancé par install.sh) : chaque commande de
#            COMMANDES_TEST doit être couverte par les permissions du round, sinon « PERMISSION MANQUANTE : <commande> » (code 1).
#   --essai <projet> : courte session claude -p, avec les vraies permissions du projet, qui exécute les commandes de
#            COMMANDES_TEST de sa fiche et liste celles qui sont refusées. Sur demande seulement (jamais dans --check).
#            Il faut que le worktree du projet existe déjà (un round a déjà tourné).
# Avec --check et en vrai round, les commandes de COMMANDES_TEST (fiche du projet) sont aussi contrôlées.
set -euo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ICI/../config.env"
source "$ICI/read-project-config.sh"
source "$ICI/resolve-model.sh"
source "$ICI/resolve-agent.sh"
source "$ICI/permissions-couverture.sh"
export PATH="$HOME/.local/bin:$BREW_BIN:/usr/bin:/bin:/usr/sbin:/sbin"

ROUND="${1:?Usage : night.sh <N|now|fiches> [--check]   ou   night.sh --essai <projet>}"
MODE="${2:-}"
# Modes hors round : « fiches » (contrôle de toutes les fiches) et « --essai <projet> » (session d'essai). Ils
# n'écrivent jamais dans reports/ ni logs/ : MODE=--check en interne (echec() n'écrit alors aucun rapport).
SPECIAL=""; ESSAI_PROJET=""
case "$ROUND" in
  fiches) SPECIAL=fiches ;;
  --essai)
    [ -z "${3:-}" ] || { echo "Option inconnue : $3 (--essai <projet> s'utilise seul, pas avec --check)"; exit 2; }
    ESSAI_PROJET="${MODE:?Usage : night.sh --essai <projet>}"
    # Le nom sert à bâtir des chemins (config/projects/<nom>.env, worktrees/<nom>) : refusé avant tout effet s'il en sort
    [[ "$ESSAI_PROJET" =~ ^[A-Za-z0-9_-]+$ && "$ESSAI_PROJET" != -* ]] \
      || { printf 'Nom de projet refusé : %q (lettres, chiffres, _ et - seulement, sans tiret en tête)\n' "$ESSAI_PROJET"; exit 2; }
    SPECIAL=essai; ROUND=essai; MODE="--check" ;;
esac
# Une option inconnue (dont l'ancienne option française) est refusée : ignorée, elle lancerait un vrai round.
case "$MODE" in
  ""|--check) ;;
  *) echo "Option inconnue : $MODE (seule --check est acceptée)"; exit 2 ;;
esac
[ "$SPECIAL" = "" ] || MODE="--check"
case "$ROUND" in
  fiches|essai)
    DATE=$(date +%F); ID="$ROUND"; FICHIER="$LAB/config/TASKS.md"; TITRE="## ROUND 0" ;;
  [1-9]|[1-9][0-9])
    # Date de NUIT : 23:00 le 27 et 02:30 le 28 donnent toutes deux le 27.
    DATE=$(date -v-12H +%F); ID="$ROUND"; FICHIER="$LAB/config/TASKS.md"; TITRE="## ROUND $ROUND" ;;
  now)
    DATE=$(date +%F); ID="now-$(date +%H%M)"; FICHIER="$LAB/config/NOW.md"; TITRE="## NOW" ;;
  *) echo "Round inconnu : $ROUND"; exit 2 ;;
esac
JOUR="$LAB/reports/$DATE"
PROJET=""

# Garde de cohérence : les garde-fous ci-dessous protègent les chemins dérivés de $LAB (lu dans config.env). Si $LAB
# n'est pas le dossier où ce script est installé (config.env copié d'ailleurs, lab déplacé, lien symbolique), ils
# protégeraient un autre dossier : le round est refusé, même avec --check. Rien n'est écrit (le rapport
# d'échec irait dans le mauvais dossier).
LAB_REEL="$(cd -P "$LAB" 2>/dev/null && pwd -P || true)"
ICI_REEL="$(cd -P "$ICI/.." && pwd -P)"
if [ -L "$LAB" ] || [ -z "$LAB_REEL" ] || [ "$LAB_REEL" != "$ICI_REEL" ]; then
  echo "ERREUR : LAB de config.env ($LAB) n'est pas le dossier de ce lab ($ICI_REEL), ou est un lien symbolique : les garde-fous ne protégeraient pas les bons fichiers. Round refusé, claude n'a pas été lancé."
  exit 1
fi

echec() {
  echo "ERREUR : $1"
  if [ "$MODE" != "--check" ]; then
    mkdir -p "$JOUR"
    printf 'STATUT: echec\n\n# Round %s — %s — %s\n\n%s\n' \
      "$ID" "${PROJET:-inconnu}" "$DATE" "$1" > "$JOUR/round-$ID-${PROJET:-inconnu}.md"
  fi
  exit 1
}

# Commit wip de fin de round (filet de sécurité) : uniquement les fichiers déjà suivis (comme git add -u),
# jamais bin/ (à tout niveau), ni un .gitignore, ni un fichier couvert par .gitignore (version de HEAD ou
# actuelle), même suivi par erreur ; ni la suppression liée à un renommage indexé. Ce qui est laissé de côté
# est listé dans le journal et à la fin du rapport. Ne fait jamais échouer le round.
# Usage : commit_wip <id> <date> [rapport], lancé à la racine du dépôt.
commit_wip() {
  local id="$1" date="$2" rapport="${3:-}" f st ancien nouveau bilan tmp mode_index ignores_head="" renommes=""
  local pris=() exclus=() suppr_renommes=() nouveaux=()
  _wip_lister() {  # <titre> <fichier>... : affiche au plus 50 fichiers
    local titre="$1"; shift
    echo "- $titre ($# fichier(s)) :"
    printf '  - %s\n' "${@:1:50}"
    [ $# -le 50 ] || echo "  - … et $(($# - 50)) autre(s)"
  }
  [ -n "$(git status --porcelain)" ] || return 0
  if ! git rev-parse -q --verify HEAD >/dev/null; then
    echo "Commit wip : dépôt sans commit initial, rien de commité."; return 0
  fi
  # Fichiers suivis ignorés selon le .gitignore racine de HEAD (l'agent a pu modifier .gitignore)
  tmp=$(mktemp "${TMPDIR:-/tmp}/wip-gitignore.XXXXXX") || tmp=""
  if [ -n "$tmp" ]; then
    git show HEAD:.gitignore >"$tmp" 2>/dev/null || :
    ignores_head=$(git ls-files -z -c -i --exclude-from="$tmp" | tr '\0' '\n') || ignores_head=""
    rm -f "$tmp"
  fi
  # Anciens noms des renommages indexés (git mv) : leur suppression n'est pas commitée sans le nouveau nom
  while IFS= read -r -d '' st && IFS= read -r -d '' ancien && IFS= read -r -d '' nouveau; do
    renommes+="$ancien"$'\n'
  done < <(git diff -z --cached --name-status -M --diff-filter=R HEAD --)
  # Fichiers suivis (présents dans HEAD) modifiés ou supprimés, dans l'index ou la copie de travail
  while IFS= read -r -d '' f; do
    if [[ "$f" == bin/* || "$f" == */bin/* || "$f" == .gitignore || "$f" == */.gitignore ]] \
      || git check-ignore -q --no-index -- "$f" || grep -qxF -- "$f" <<<"$ignores_head"; then
      exclus+=("$f")
    elif grep -qxF -- "$f" <<<"$renommes"; then
      suppr_renommes+=("$f")
    else
      pris+=("$f")
    fi
  done < <(git diff -z --name-only --no-renames --diff-filter=MDT HEAD --)
  # Fichiers jamais suivis : non suivis (hors .gitignore) ou ajoutés à l'index sans être commités
  while IFS= read -r -d '' f; do nouveaux+=("$f"); done < <(
    git ls-files -z --others --exclude-standard
    git diff -z --cached --name-only --no-renames --diff-filter=A HEAD --)
  if [ ${#pris[@]} -eq 0 ]; then
    bilan="aucun fichier suivi à prendre, rien de commité."
  else
    # « commit --only » relit les fichiers sur le disque : un script en 755 dans l'index mais en 644 sur le disque
    # (chmod refusé aux agents ; seul « git add --chmod=+x » marche) serait commité en 644. Le mode de l'index fait foi :
    # on rend le bit d'exécution au fichier avant le commit (cas réels : commits 6dedb75 et f6c7a82).
    for f in "${pris[@]}"; do
      [ -f "$f" ] && [ ! -L "$f" ] && [ ! -x "$f" ] || continue
      mode_index="$(git --literal-pathspecs ls-files -s -- "$f" 2>/dev/null)" || mode_index=""
      if [ "${mode_index%% *}" = 100755 ]; then chmod +x -- "$f" 2>/dev/null || :; fi
    done
    if git --literal-pathspecs commit -q --only -m "wip(claude): état en fin de round $id ($date)" -- "${pris[@]}"; then
      bilan="commit $(git rev-parse --short HEAD) (fichiers suivis seulement)."
    else
      bilan="commit échoué (voir le journal), rien de commité."
    fi
  fi
  {
    printf '\n## Commit wip de fin de round (ajouté par night.sh)\n\n- Commit wip : %s\n' "$bilan"
    [ ${#pris[@]} -eq 0 ] || _wip_lister "Fichiers suivis pris dans le commit" "${pris[@]}"
    [ ${#exclus[@]} -eq 0 ] || _wip_lister "Laissés de côté, suivis mais dans bin/, .gitignore ou couverts par .gitignore" "${exclus[@]}"
    [ ${#suppr_renommes[@]} -eq 0 ] || _wip_lister "Laissés de côté, suppressions liées à un renommage indexé" "${suppr_renommes[@]}"
    [ ${#nouveaux[@]} -eq 0 ] || _wip_lister "Laissés de côté, non suivis (jamais commités par night.sh)" "${nouveaux[@]}"
  } | tee -a ${rapport:+"$rapport"} || echo "Commit wip : rapport non complété ($rapport)."
}

# --- 1. Source des tâches -------------------------------------------------
if [ "$MODE" = "--check" ]; then
  SOURCE="$FICHIER"
else
  mkdir -p "$JOUR" "$LOGS" "$WORKTREES"
  exec >>"$LOGS/$DATE-round-$ID.log" 2>&1
  echo "=== Round $ID — $(date) ==="
  if [ "$ROUND" = now ]; then
    # Signal pour run-now.sh ; retiré en fin de round, quoi qu'il arrive.
    echo "$JOUR round-$ID" > "$LAB/.now-running"
    trap 'rm -f "$LAB/.now-running"' EXIT
    SOURCE="$JOUR/tasks-$ID.md"
    cp "$FICHIER" "$SOURCE"
    cp "$LAB/templates/NOW.empty.md" "$FICHIER"      # jamais exécuté deux fois
  else
    # Chaque round de nuit relit config/TASKS.md et en archive une copie dans tasks-night.md
    # (écrasée à chaque round : une copie laissée par un test de journée n'est jamais réutilisée).
    cp "$FICHIER" "$JOUR/tasks-night.md"
    touch "$LAB/.night-running"
    SOURCE="$JOUR/tasks-night.md"
  fi
fi

# --- 2. Extraire la section du round (commentaires HTML ignorés) ---------
SECTION=$(awk '/<!--/{c=1} !c{print} /-->/{c=0}' "$SOURCE" \
  | awk -v r="$TITRE" '/^## /{sub(/[[:space:]]+$/,""); dans=($0==r); next} dans{print}')

PROJET=$(sed -n 's/^projet:[[:space:]]*//p' <<<"$SECTION" | awk 'NR==1{gsub(/[[:space:]]/,""); print}')
BRANCHE=$(sed -n 's/^branche:[[:space:]]*//p' <<<"$SECTION" | awk 'NR==1{gsub(/[[:space:]]/,""); print}')
NB=$(grep -cE '^- \[[a-z0-9-]+\]' <<<"$SECTION" || true)
# --essai : le projet vient de la ligne de commande (pas de tâches lues)
[ -z "$ESSAI_PROJET" ] || { PROJET="$ESSAI_PROJET"; BRANCHE="claude/essai"; NB=1; }

if [ "$SPECIAL" != fiches ] && { [ -z "$PROJET" ] || [ "$NB" -eq 0 ]; }; then
  echo "Round $ID : aucune tâche, rien à faire."
  exit 0
fi

# --- 3. Validations -------------------------------------------------------
# (mode « fiches » : pas de projet unique, la boucle sur les fiches est plus bas, après construire_permissions)
if [ "$SPECIAL" != fiches ]; then
# Le nom du projet sert à bâtir des chemins (fiche, worktree, rapport) : il est filtré avant tout usage. Le nom refusé
# n'est pas gardé dans PROJET (echec() l'écrirait dans le nom du rapport).
if ! [[ "$PROJET" =~ ^[A-Za-z0-9_-]+$ && "$PROJET" != -* ]]; then
  PROJET_REFUSE="$PROJET"; PROJET=""
  echec "$(printf 'Nom de projet refusé : %q (lettres, chiffres, _ et - seulement, sans tiret en tête).' "$PROJET_REFUSE")"
fi
[[ "$BRANCHE" == claude/* ]] || echec "Branche « $BRANCHE » refusée : elle doit commencer par claude/."
git check-ref-format --branch "$BRANCHE" >/dev/null 2>&1 || echec "Nom de branche invalide : $BRANCHE"
[ -f "$LAB/config/projects/$PROJET.env" ] || echec "Projet inconnu : $PROJET (config/projects/$PROJET.env absent)."
MODELE=""; COMMANDES_TEST=""
lire_fiche "$LAB/config/projects/$PROJET.env"
[ -d "$REPO_PATH/.git" ] || echec "Dépôt introuvable : $REPO_PATH"

# Cerveau (modèle) des rounds : projet (clé MODELE de la fiche), sinon lab (MODELE_LAB de config.env ; à défaut
# ANTHROPIC_MODEL, ancien réglage). Le niveau agent est appliqué par claude lui-même (champ model: de chaque
# agents/<nom>.md ; « inherit » = ce modèle). Priorité : agent > projet > lab (voir resolve-model.sh).
MODELE_RETENU=$(resoudre_modele_source "" "${MODELE:-}" "${MODELE_LAB:-${ANTHROPIC_MODEL:-}}") || MODELE_RETENU=""
if [ -n "$MODELE_RETENU" ]; then
  export ANTHROPIC_MODEL="${MODELE_RETENU%%$'\t'*}"
  echo "Modèle des rounds : ${MODELE_RETENU%%$'\t'*} (niveau ${MODELE_RETENU#*$'\t'})"
else
  echo "Modèle des rounds : aucun réglage (MODELE_LAB vide), claude utilisera son défaut."
fi
for TAG in $(grep -oE '^- \[[a-z0-9-]+\]' <<<"$SECTION" | sed -E 's/^- \[(.*)\]$/\1/' | sort -u); do
  # agents/<tag>.md (général) ou agents/<projet>/<tag>.md (projet du round) ; le général gagne (voir resolve-agent.sh)
  if AGENT_FICHIER=$(trouver_agent "$LAB/agents" "$PROJET" "$TAG"); then
    AGENT_MODELE=$(resoudre_modele_source "$AGENT_FICHIER" "${MODELE:-}" "${MODELE_LAB:-${ANTHROPIC_MODEL:-}}") || AGENT_MODELE=""
    echo "  [$TAG] modèle : ${AGENT_MODELE%%$'\t'*} (niveau ${AGENT_MODELE#*$'\t'})"
  else
    echo "  [$TAG] pas d'agents/$TAG.md ni d'agents/$PROJET/$TAG.md dans le lab (agent propre au dépôt du projet ? sinon la tâche sera marquée ❌)"
  fi
done
fi   # fin du « if [ "$SPECIAL" != fiches ] » ouvert aux validations

# Chemin d'un dossier sous forme de motif de permission : ~/… s'il est dans le dossier personnel, sinon //chemin
# (forme absolue de Claude Code). Les garde-fous ci-dessous en dérivent de $LAB : aucun chemin écrit en dur.
motif_chemin() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '/%s' "$1" ;; esac; }
LAB_MOTIF="$(motif_chemin "$LAB")"

# Permissions des agents : OUTILS (--allowedTools) et INTERDITS (--disallowedTools). Un interdit l'emporte
# toujours sur un autorisé ; une commande Bash absente des autorisés est refusée (pas de question en -p).
# Motifs et raisons : optimisation-systeme, correctifs/permissions/ (notice du projet d'origine).
construire_permissions() {
  local p
  OUTILS="Read,Glob,Grep,Edit,Write,TodoWrite,Task,Agent,WebSearch,WebFetch"
  OUTILS+=",Bash(git status*),Bash(git diff*),Bash(git log*),Bash(git show*),Bash(git add *),Bash(git commit *),Bash(ls *)"
  OUTILS+=",Bash(git --version)"
  [ -n "${OUTILS_EXTRA:-}" ] && OUTILS+=",$OUTILS_EXTRA"

  INTERDITS="Bash(git push*),Bash(git switch*),Bash(git checkout*),Bash(git merge*),Bash(git rebase*)"
  INTERDITS+=",Bash(git reset --hard*),Bash(*--no-verify*),Bash(rm -rf*),Bash(sudo *),Bash(gh *)"
  # Autres formes de rm récursif ; options de git qui visent un autre dépôt (git -C <chemin> push…) ;
  # --output de git diff/log/show, qui écrit un fichier n'importe où (contournerait les Edit interdits).
  INTERDITS+=",Bash(rm -fr*),Bash(rm -Rf*),Bash(rm -fR*),Bash(rm -r *),Bash(rm -R *)"
  INTERDITS+=",Bash(git -C *),Bash(git -c *),Bash(git --git-dir*),Bash(git --work-tree*),Bash(git *--output*)"
  # git diff --no-index et git commit -F/--file lisent n'importe quel fichier (~/.ssh compris) ;
  # -n est la forme courte de --no-verify.
  INTERDITS+=",Bash(git *--no-index*),Bash(git commit *-F*),Bash(git commit *--file*),Bash(git commit -n*),Bash(git commit * -n)"
  # Fichiers du lab et du compte : jamais modifiables par un agent (le rapport, dans reports/, reste permis).
  for p in 'scripts/**' config.env 'config/projects/**' 'prompts/**' 'agents/**' 'templates/**' 'memory/**' '.claude/**' CLAUDE.md 'config/TASKS.md' 'config/NOW.md'; do
    INTERDITS+=",Edit($LAB_MOTIF/$p)"
  done
  INTERDITS+=",Edit(~/Library/LaunchAgents/**),Edit(~/.claude/**),Edit(~/.ssh/**),Read(~/.ssh/**),Edit(~/.local/bin/**)"
  INTERDITS+=",Edit(~/.zshrc),Edit(~/.zprofile),Edit(~/.zshenv),Edit(~/.bash_profile),Edit(~/.bashrc),Edit(~/.profile)"
  # Identifiants, trousseaux et historiques du compte : jamais lus (Read est autorisé partout ailleurs).
  INTERDITS+=",Read(~/.aws/**),Read(~/.gnupg/**),Read(~/.config/gh/**),Read(~/.netrc),Read(~/.git-credentials)"
  INTERDITS+=",Read(~/.claude/.credentials.json),Read(~/.zsh_history),Read(~/.bash_history),Read(~/Library/Keychains/**)"
  [ -n "${INTERDITS_EXTRA:-}" ] && INTERDITS+=",$INTERDITS_EXTRA"
  return 0
}

# Garde avant le lancement : verifier_permissions <autorisés> <interdits> affiche chaque problème
# (« PERMISSIONS : … ») et renvoie 1 s'il y en a un. Contrôle : motifs « Outil » ou « Outil(argument) »
# séparés par une virgule seule (pas d'espace, pas de virgule ni de parenthèse dans l'argument, rien de vide),
# outil connu ; dans les autorisés, pas de Bash générique (Bash, Bash(*), joker en tête, interpréteur ou
# commande générique suivi d'un joker sans chemin ni sous-commande, ou dont le premier argument hors options
# est absolu, commence par ~ ou $, ou contient « .. », VAR=* devant une commande) ; aucun
# autorisé déjà couvert par un interdit ; interdits critiques présents. Ce n'est pas un bac à sable : un
# script autorisé (ex. zsh tools/*) peut toujours tout faire.
verifier_permissions() {
  local autorises="$1" interdits="$2" ok=0 genre liste m nom arg parens premier p a mot large
  local re='^([A-Za-z][A-Za-z0-9_]*)(\(([^(),]+)\))?$'
  local connus=" Read Glob Grep Edit Write MultiEdit NotebookEdit TodoWrite Task Agent WebSearch WebFetch Bash "
  local generiques=" bash sh zsh dash ksh fish csh tcsh python python3 node perl ruby php osascript eval exec env xargs find awk sed git command nohup source"
  generiques+=" cat cp mv tee dd curl wget ssh scp rsync security launchctl defaults open kill chmod ln tar "
  local motifs interdits_l critiques
  # Interdits critiques, recopiés exprès ici (et non lus dans construire_permissions) : un retrait par erreur se voit.
  # Le chemin du lab, lui, est dérivé de $LAB comme dans construire_permissions (même fonction motif_chemin).
  critiques=("Bash(git push*)" "Bash(rm -rf*)" "Bash(sudo *)" "Bash(git reset --hard*)" "Bash(*--no-verify*)"
             "Read(~/.ssh/**)" "Edit(~/.ssh/**)")
  for p in 'scripts/**' config.env 'config/projects/**' 'prompts/**' 'agents/**' 'templates/**' 'memory/**' '.claude/**' CLAUDE.md 'config/TASKS.md' 'config/NOW.md'; do
    critiques+=("Edit($LAB_MOTIF/$p)")
  done
  for genre in autorises interdits; do
    if [ "$genre" = autorises ]; then liste="$autorises"; else liste="$interdits"; fi
    case "$liste" in
      ""|,*|*,|*,,*|*$'\n'*) echo "PERMISSIONS : liste des $genre vide, motif vide ou retour à la ligne"; ok=1; continue ;;
    esac
    IFS=, read -ra motifs <<<"$liste"
    for m in "${motifs[@]}"; do
      if ! [[ "$m" =~ $re ]]; then
        echo "PERMISSIONS : motif mal formé dans les $genre : « $m »"; ok=1; continue
      fi
      nom="${BASH_REMATCH[1]}"; parens="${BASH_REMATCH[2]}"; arg="${BASH_REMATCH[3]}"
      if [[ "$connus" != *" $nom "* && "$nom" != mcp__* ]]; then
        echo "PERMISSIONS : outil inconnu dans les $genre : « $m »"; ok=1; continue
      fi
      if [ -n "$parens" ] && [[ "$arg" != *[!*[:space:]]* ]]; then
        echo "PERMISSIONS : argument vide ou joker seul dans les $genre : « $m »"; ok=1; continue
      fi
      [ "$genre" = autorises ] && [ "$nom" = Bash ] || continue
      large=""
      if [ -z "$parens" ] || [[ "$arg" == [*[:space:]]* ]]; then
        large="Bash sans motif ou motif commençant par un joker"
      else
        premier="${arg%% *}"
        if [[ "$premier" == *=* && "$arg" == *\** ]]; then
          large="affectation de variable avec joker"
        else
          p="${premier%%\**}"; p="${p##*/}"
          if [[ "$generiques" == *" $p "* ]]; then
            # Premier argument hors options : il ne doit pas sortir du dépôt.
            a="${arg#"$premier"}"
            while [[ "$a" =~ ^[[:space:]]*([^[:space:]]+)(.*)$ ]]; do
              mot="${BASH_REMATCH[1]}"; a="${BASH_REMATCH[2]}"
              if [[ "$mot" != -* ]]; then
                case "$mot" in
                  /*|"~"*|\$*|*..*) large="commande générique avec un chemin absolu, ~, \$ ou .. : « $mot »" ;;
                esac
                break
              fi
            done
            if [ -n "$large" ]; then
              :
            elif [[ "$arg" == *\** ]]; then
              # Avant le premier joker, il faut un mot qui n'est pas une option (chemin, sous-commande).
              large="commande générique suivie d'un joker sans chemin ni sous-commande"
              a="${arg%%\**}"; a="${a#"${a%% *}"}"
              while [[ "$a" =~ ^[[:space:]]*([^[:space:]]+)(.*)$ ]]; do
                mot="${BASH_REMATCH[1]}"; a="${BASH_REMATCH[2]}"
                if [[ "$mot" != -* ]]; then large=""; break; fi
              done
            elif [[ "$arg" != *" "* ]]; then
              large="interpréteur ou commande générique seul"
            fi
          fi
        fi
      fi
      if [ -n "$large" ]; then echo "PERMISSIONS : autorisation trop large ($large) : « $m »"; ok=1; fi
    done
  done
  # Autorisé déjà couvert par un interdit du même outil : il ne sert à rien, c'est une erreur de liste.
  if [ -n "$autorises" ] && [ -n "$interdits" ]; then
    IFS=, read -ra motifs <<<"$autorises"
    IFS=, read -ra interdits_l <<<"$interdits"
    for m in "${motifs[@]}"; do
      [[ "$m" =~ $re ]] && [ -n "${BASH_REMATCH[2]}" ] || continue
      nom="${BASH_REMATCH[1]}"; arg="${BASH_REMATCH[3]}"
      for a in "${interdits_l[@]}"; do
        [[ "$a" =~ $re ]] && [ "${BASH_REMATCH[1]}" = "$nom" ] && [ -n "${BASH_REMATCH[2]}" ] || continue
        p="${BASH_REMATCH[3]}"
        if [[ "$arg" == $p ]]; then echo "PERMISSIONS : autorisé « $m » couvert par l'interdit « $a »"; ok=1; fi
      done
    done
  fi
  for p in "${critiques[@]}"; do
    case ",$interdits," in
      *",$p,"*) ;;
      *) echo "PERMISSIONS : interdit critique absent : « $p »"; ok=1 ;;
    esac
  done
  return "$ok"
}

# Mode « fiches » (lancé par install.sh) : chaque fiche qui déclare COMMANDES_TEST est contrôlée avec SES permissions
# (OUTILS_EXTRA, INTERDITS_EXTRA), construites par la même construire_permissions que pour un round.
if [ "$SPECIAL" = fiches ]; then
  FICHES_KO=0; NB_FICHES=0
  for FICHE in "$LAB"/config/projects/*.env; do
    [ -f "$FICHE" ] || continue
    NOM_FICHE="$(basename "$FICHE" .env)"
    OUTILS_EXTRA=""; INTERDITS_EXTRA=""; COMMANDES_TEST=""
    lire_fiche "$FICHE"
    [ -n "$COMMANDES_TEST" ] || continue
    NB_FICHES=$((NB_FICHES + 1))
    construire_permissions
    # Même garde que pour un round (autorisation trop large, motif mal formé…) : une fiche fautive est KO
    if ! SORTIE_PERM="$(verifier_permissions "$OUTILS" "$INTERDITS")"; then
      echo "  $NOM_FICHE : permissions invalides (OUTILS_EXTRA / INTERDITS_EXTRA)"
      echo "$SORTIE_PERM"
      FICHES_KO=1
      continue
    fi
    if SORTIE_FICHE="$(commandes_manquantes "$COMMANDES_TEST" "$OUTILS" "$INTERDITS")"; then
      echo "  $NOM_FICHE : $(compter_commandes "$COMMANDES_TEST") commande(s) de test couverte(s)"
    else
      echo "  $NOM_FICHE : commande(s) de test NON couverte(s) par les permissions"
      echo "$SORTIE_FICHE"
      FICHES_KO=1
    fi
  done
  [ "$NB_FICHES" -gt 0 ] || echo "Aucune fiche ne déclare COMMANDES_TEST : rien à contrôler."
  [ "$FICHES_KO" -eq 0 ] || echo "ERREUR : des fiches ont des permissions invalides ou des commandes de test non couvertes (OUTILS_EXTRA / INTERDITS_EXTRA de la fiche concernée)."
  exit "$FICHES_KO"
fi

# Garde lancée aussi par --check (contrôle à blanc de la fiche), et, en vrai round, avant tout effet
# sur le dépôt (worktree non préparé, claude non lancé) si elle échoue.
construire_permissions
if ! verifier_permissions "$OUTILS" "$INTERDITS"; then
  if [ "$MODE" = "--check" ]; then DETAIL="ci-dessus"; else DETAIL="dans logs/$DATE-round-$ID.log"; fi
  echec "Permissions invalides (OUTILS_EXTRA / INTERDITS_EXTRA de config/projects/$PROJET.env, ou listes de night.sh) : détail $DETAIL. claude n'a pas été lancé."
fi

# Commandes de test déclarées par la fiche (COMMANDES_TEST) : chacune doit être couverte par OUTILS (+ OUTILS_EXTRA)
# et non bloquée par un interdit, sinon l'agent la verrait refusée en pleine nuit. Fiche sans la clé : rien.
COMMANDES_TEST_KO=0
if [ -n "$COMMANDES_TEST" ]; then
  if commandes_manquantes "$COMMANDES_TEST" "$OUTILS" "$INTERDITS"; then
    echo "Commandes de test : $(compter_commandes "$COMMANDES_TEST") couverte(s)"
  else
    COMMANDES_TEST_KO=1
  fi
fi
if [ "$COMMANDES_TEST_KO" -eq 1 ] && [ "$SPECIAL" != essai ]; then
  echec "Commandes de test non couvertes par les permissions (COMMANDES_TEST / OUTILS_EXTRA de config/projects/$PROJET.env) : voir « PERMISSION MANQUANTE » ci-dessus. claude n'a pas été lancé."
fi

# --- Essai des permissions (night.sh --essai <projet>) : courte session claude -p avec les vraies permissions ---
if [ "$SPECIAL" = essai ]; then
  if [ -z "$COMMANDES_TEST" ]; then
    echo "Essai : la fiche $PROJET ne déclare pas COMMANDES_TEST (commandes de test à essayer, séparées par |) : rien à essayer."
    exit 0
  fi
  WT="$WORKTREES/$PROJET"
  [ -d "$WT" ] || echec "Worktree absent ($WT) : l'essai tourne dans le worktree du projet, jamais dans le dépôt de base. Lancez d'abord un round sur ce projet."
  LISTE_ESSAI=""
  IFS='|' read -ra CMDS_ESSAI <<<"$COMMANDES_TEST"
  for CMD in "${CMDS_ESSAI[@]}"; do
    CMD="${CMD#"${CMD%%[![:space:]]*}"}"; CMD="${CMD%"${CMD##*[![:space:]]}"}"
    [ -z "$CMD" ] || LISTE_ESSAI+="- $CMD"$'\n'
  done
  NB_ESSAI="$(compter_commandes "$COMMANDES_TEST")"
  PROMPT_ESSAI="Essai des permissions du projet $PROJET (aucune tâche à faire, rien à modifier).
Pour chaque commande ci-dessous, exécute-la TELLE QUELLE avec l'outil Bash, depuis le dossier courant (la racine du
worktree), une commande par appel. Ne la modifie pas, ne la contourne pas : si les permissions la refusent, passe à la
suivante sans essayer autre chose. Peu importe qu'elle réussisse ou échoue (tests rouges) : seul compte le refus.
Termine par une ligne par commande : « OK : <commande> » si elle a pu être lancée, « REFUSÉE : <commande> » si
les permissions l'ont refusée.

Commandes :
$LISTE_ESSAI"
  # L'essai ne modifie rien : ni Edit ni Write (ni MultiEdit, NotebookEdit), même venus de OUTILS_EXTRA. Les interdits restent entiers.
  OUTILS_ESSAI=""
  IFS=, read -ra OUTILS_L <<<"$OUTILS"
  for OUTIL in "${OUTILS_L[@]}"; do
    case "$OUTIL" in Edit|Edit\(*|Write|Write\(*|MultiEdit|MultiEdit\(*|NotebookEdit|NotebookEdit\(*) continue ;; esac
    OUTILS_ESSAI+="${OUTILS_ESSAI:+,}$OUTIL"
  done
  # Lecture seule aussi côté interdits (essai seulement) : les outils d'écriture, sans argument, s'ajoutent aux interdits.
  INTERDITS_ESSAI="$INTERDITS,Edit,Write,MultiEdit,NotebookEdit"
  echo "Essai des permissions : $NB_ESSAI commande(s) dans $WT (claude -p, vraies permissions de la fiche $PROJET, sans Edit ni Write)."
  cd "$WT"
  set +e
  SORTIE_ESSAI="$(gtimeout 600 claude -p "$PROMPT_ESSAI" \
    --allowedTools "$OUTILS_ESSAI" \
    --disallowedTools "$INTERDITS_ESSAI" \
    --permission-mode acceptEdits \
    --max-turns "$((NB_ESSAI * 3 + 6))" 2>&1)"
  CODE_ESSAI=$?
  set -e
  echo "$SORTIE_ESSAI"
  REFUSEES="$(sed -n 's/^[[:space:]]*REFUSÉE[[:space:]]*:[[:space:]]*//p' <<<"$SORTIE_ESSAI")"
  if [ -n "$REFUSEES" ]; then
    while IFS= read -r CMD; do echo "PERMISSION MANQUANTE : $CMD"; done <<<"$REFUSEES"
    COMMANDES_TEST_KO=1
  fi
  if [ "$CODE_ESSAI" -ne 0 ]; then echo "ERREUR : claude a terminé avec le code $CODE_ESSAI."; COMMANDES_TEST_KO=1; fi
  # Chaque commande doit avoir sa ligne « OK : » : une réponse tronquée (max-turns, bavardage) n'est pas un succès.
  NB_OK="$(grep -cE '^[[:space:]]*OK[[:space:]]*:' <<<"$SORTIE_ESSAI" || true)"
  if [ "$NB_OK" -lt "$NB_ESSAI" ]; then
    echo "ERREUR : $NB_OK ligne(s) « OK : » dans la sortie de claude pour $NB_ESSAI commande(s) : essai incomplet, rien n'est prouvé."
    COMMANDES_TEST_KO=1
  fi
  if [ "$COMMANDES_TEST_KO" -eq 1 ]; then exit 1; fi
  echo "Essai : toutes les commandes de test ont pu être lancées."
  exit 0
fi

if [ "$MODE" = "--check" ]; then
  echo "OK — round $ROUND : $NB tâche(s) sur « $PROJET », branche $BRANCHE"
  exit 0
fi

# --- 4. Préparer le worktree sur la branche claude/* ---------------------
WT="$WORKTREES/$PROJET"
bash "$LAB/scripts/prepare-worktree.sh" "$PROJET" "$BRANCHE" "$WT" \
  || echec "Préparation du worktree impossible (voir logs/$DATE-round-$ID.log)"
cd "$WT"

# --- 5. Lancer le chef de nuit -------------------------------------------
RAPPORT="$JOUR/round-$ID-$PROJET.md"

PROMPT="Round $ID du $DATE.
Projet : $PROJET
Dépôt (worktree) : $WT
Branche de travail (déjà active) : $BRANCHE
Fiche projet : $LAB/config/projects/$PROJET.md
Rapport à écrire : $RAPPORT

Tâches de ce round :
$SECTION"

# Commandes de test de la fiche (clé COMMANDES_TEST) : les seules dont les permissions sont vérifiées, à lancer telles quelles
if [ -n "$COMMANDES_TEST" ]; then
  LISTE_TESTS=""
  IFS='|' read -ra CMDS_TEST <<<"$COMMANDES_TEST"
  for CMD in "${CMDS_TEST[@]}"; do
    CMD="${CMD#"${CMD%%[![:space:]]*}"}"; CMD="${CMD%"${CMD##*[![:space:]]}"}"
    [ -z "$CMD" ] || LISTE_TESTS+="- $CMD"$'\n'
  done
  PROMPT="$PROMPT

Commandes de test du projet (fiche, clé COMMANDES_TEST) : lance-les TELLES QUELLES, depuis la racine du worktree,
en chemin relatif (jamais en chemin absolu, jamais enchaînées avec && ou ;) : toute autre forme serait refusée.
$LISTE_TESTS"
fi

# Reprise après une limite hebdomadaire (REPRISE_MOTIF=hebdo, posé par night-chain.sh) : la nuit n'a pas été
# arrêtée. « , nuit arrêtée » est retiré des lignes « ARRÊT : limite hebdomadaire … » (en début de ligne,
# écrites par annoter_arret). Si le rapport est le rapport minimal d'annoter_arret (ligne « Aucun rapport écrit
# (code de sortie N). Voir … » en début de ligne), il n'est pas supprimé : « STATUT: echec » passe en
# « STATUT: partiel » et seule la phrase « Aucun rapport écrit (code de sortie N). » est retirée (D1 B : la ligne
# ARRÊT et le renvoi au journal restent, même si la reprise est coupée à son tour sans rapport). Le reste du
# rapport est inchangé, et le fichier n'est pas réécrit s'il n'y a rien à corriger. Rapport absent, vide ou lien
# symbolique : rien. Positionne RAPPORT_REPRISE_CORRIGE (1 si le rapport a été corrigé, 0 sinon : message de la
# reprise). Muette sauf en cas d'erreur ; ne fait jamais échouer le round.
# Usage : rapport_reprise_hebdo <rapport>
rapport_reprise_hebdo() {
  local rapport="${1:-}" tmp="" mini=0
  RAPPORT_REPRISE_CORRIGE=0
  [ -n "$rapport" ] && [ ! -L "$rapport" ] && [ -s "$rapport" ] || return 0
  grep -q '^Aucun rapport écrit (code de sortie ' "$rapport" 2>/dev/null && mini=1
  tmp=$(mktemp "${TMPDIR:-/tmp}/reprise-hebdo.XXXXXX") || { echo "Reprise : rapport non corrigé ($rapport)."; return 0; }
  # awk sort en 1 si aucune ligne n'est corrigée (ou en erreur) : rapport laissé tel quel.
  if awk -v d="ARRÊT : limite hebdomadaire" -v n=", nuit arrêtée à " -v m="$mini" '
       m == 1 && NR == 1 && $0 == "STATUT: echec" { $0 = "STATUT: partiel"; c++ }
       index($0, d) == 1 && (i = index($0, n)) { $0 = substr($0, 1, i - 1) " à " substr($0, i + length(n)); c++ }
       m == 1 && sub(/^Aucun rapport écrit \(code de sortie [0-9]+\)\. ?/, "") { c++ }
       { print } END { exit !c }' "$rapport" > "$tmp" 2>/dev/null; then
    if cat "$tmp" > "$rapport"; then RAPPORT_REPRISE_CORRIGE=1; else echo "Reprise : rapport non corrigé ($rapport)."; fi
  fi
  rm -f "$tmp"
  return 0
}

# Reprise après une limite de session ou hebdomadaire (REPRISE=1 et REPRISE_MOTIF, posés par night-chain.sh ;
# sans REPRISE_MOTIF=hebdo, limite de session comme avant : le rapport minimal est supprimé)
if [ "${REPRISE:-}" = 1 ]; then
  COUPURE="limite de session"
  if [ "${REPRISE_MOTIF:-}" = hebdo ]; then
    COUPURE="limite hebdomadaire"
    rapport_reprise_hebdo "$RAPPORT" || :
    if [ "$RAPPORT_REPRISE_CORRIGE" = 1 ]; then
      echo "Reprise après une limite hebdomadaire : rapport corrigé (« nuit arrêtée » retiré, rapport minimal passé en partiel s'il y était ; la nuit continue)."
    fi
  else
    grep -q "Aucun rapport écrit" "$RAPPORT" 2>/dev/null && rm -f "$RAPPORT"
  fi
  QUAND="il reprend après la remise à zéro"
  if [ "${REPRISE_MOTIF:-}" = timeout ]; then       # durée max TIMEOUT_ROUND (relance par night-chain.sh, sans attente)
    COUPURE="limite de temps du round (TIMEOUT_ROUND)"; QUAND="il reprend tout de suite sur la même branche"
  fi
  PROMPT="REPRISE : ce round a été coupé par la $COUPURE, $QUAND.
Si le rapport $RAPPORT existe, lis-le ainsi que git log : ne refais pas les tâches déjà terminées et commitées,
reprends à la première tâche non terminée et complète ce rapport sans effacer ce qui y est.
Garde les lignes « ARRÊT : … » sous STATUT (historique des coupures) et, à la fin, remets la ligne STATUT à jour.

$PROMPT"
fi

# Agents du lab fournis au round par --agents (JSON) : généraux (agents/*.md) puis agents du projet (agents/<projet>/*.md),
# le général gagne, modèle résolu agent > projet > lab (voir scripts/agents_round.py). Le JSON est passé en un seul
# argument (jamais par eval ni par le shell). Échec ou aucun agent : le round part sans --agents (avertissement).
OPT_AGENTS=()
if AGENTS_JSON="$(python3 "$ICI/agents_round.py" "$LAB/agents" "$PROJET" --modele-projet "${MODELE:-}" --modele-lab "${MODELE_LAB:-${ANTHROPIC_MODEL:-}}")"; then
  [ "$AGENTS_JSON" = "{}" ] || OPT_AGENTS=(--agents "$AGENTS_JSON")
else
  echo "ATTENTION : agents du lab non fournis au round (agents_round.py a échoué) ; claude utilisera ses agents par défaut."
fi

# caffeinate -i : empêche toute mise en veille pendant le round ; gtimeout : durée maximale
set +e
caffeinate -i gtimeout "$TIMEOUT_ROUND" claude -p "$PROMPT" \
  ${OPT_AGENTS[@]+"${OPT_AGENTS[@]}"} \
  --append-system-prompt "$(cat "$LAB/prompts/night.md")" \
  --allowedTools "$OUTILS" \
  --disallowedTools "$INTERDITS" \
  --permission-mode acceptEdits \
  --add-dir "$JOUR" \
  --max-turns "$MAX_TURNS"
CODE=$?
set -e
echo "claude a terminé (code $CODE) — $(date)"

# --- 6. Filets de sécurité après le round --------------------------------
# Motif d'arrêt. Si claude s'est arrêté anormalement (code 124 : durée max TIMEOUT_ROUND ; code non nul et
# message « You've hit your session limit » : limite de session ; code non nul et « Reached max turns » :
# MAX_TURNS ; tout autre code non nul : erreur), le rapport reçoit en DEUXIÈME ligne
# « ARRÊT : <motif> à HH:MM ». La première ligne reste « STATUT: … » (lue par la PR et le manageur) : elle
# passe à partiel, sauf si elle disait déjà partiel ou echec (casse ignorée), et elle est ajoutée si elle
# manquait. Rapport absent ou vide : rapport minimal « STATUT: echec » comme avant (« STATUT: partiel »
# après une limite de session : le round reprendra), plus la ligne ARRÊT si l'arrêt est anormal.
# Fin normale : rapport inchangé. Seule la sortie de la dernière tentative est lue dans le journal
# (après la dernière ligne « === Round », avant « claude a terminé »). Aucun message d'erreur n'est
# recopié : le rapport devient la description de la PR. Un rapport qui est un lien symbolique n'est jamais
# touché. Ne fait jamais échouer le round. Défini ici (et non après echec()) pour que ce correctif reste
# indépendant du correctif wip-commit.
# Usage : annoter_arret <code> <journal> <rapport> <id> <projet> <date> [HH:MM]
annoter_arret() {
  local code="${1:-}" journal="$2" rapport="$3" id="$4" projet="$5" date="$6" heure="${7:-}"
  local c="${1:-?}" sortie="" motif="" resets="" ligne1="" statut="" tmp="" debut=1 minimal="echec"
  local re='^STATUT:[[:space:]]*(.*)$'
  [ -n "$heure" ] || heure=$(date +%H:%M)
  if [ -f "$journal" ]; then
    sortie=$(awk 'BEGIN{f=1} /^=== Round /{b=""; f=1} /^claude a terminé/{f=0} f{b=b $0 "\n"} END{printf "%s", b}' \
      "$journal") || sortie=""
  fi
  if [ "$code" = 124 ]; then
    motif="durée max atteinte (TIMEOUT_ROUND=${TIMEOUT_ROUND:-?}, code 124)"
  elif [ "$code" != 0 ] && grep -qE '^(Error: )?You.{1,3}ve hit your weekly limit' <<<"$sortie"; then
    # Limite hebdomadaire : night-chain.sh arrête la nuit, ou reprend si la remise tombe avant le dernier départ
    # (la REPRISE retire alors « , nuit arrêtée » et le rapport minimal, voir rapport_reprise_hebdo) ; minimal en echec.
    resets=$(grep -oE 'resets ([A-Z][a-z]{2} )?[0-9]{1,2}(:[0-9]{2})?[ap]m' <<<"$sortie" | tail -n 1) || resets=""
    motif="limite hebdomadaire${resets:+, $resets} (code $c), nuit arrêtée"
  elif [ "$code" != 0 ] && grep -qE '^(Error: )?You.{1,3}ve hit your session limit' <<<"$sortie"; then
    resets=$(grep -oE 'resets [0-9]{1,2}(:[0-9]{2})?[ap]m' <<<"$sortie" | tail -n 1) || resets=""
    motif="limite de session${resets:+, $resets} (code $c)"; minimal="partiel"
  elif [ "$code" != 0 ] && grep -qE '^(Error: )?Reached max turns' <<<"$sortie"; then
    motif="max-turns atteint (MAX_TURNS=${MAX_TURNS:-?}, code $c)"
  elif [ "$code" != 0 ]; then
    motif="erreur (code $c, voir logs/${journal##*/})"
  fi
  if [ -L "$rapport" ]; then                        # lien symbolique : jamais réécrit ni suivi
    echo "Motif d'arrêt : rapport non annoté ($rapport est un lien symbolique)."; return 0
  fi
  # Rapport absent ou vide : rapport minimal (la phrase « Aucun rapport écrit » sert à la REPRISE)
  if [ ! -s "$rapport" ]; then
    {
      echo "STATUT: $minimal"
      [ -z "$motif" ] || echo "ARRÊT : $motif à $heure"
      printf '\n# Round %s — %s — %s\n\nAucun rapport écrit (code de sortie %s). Voir logs/%s-round-%s.log\n' \
        "$id" "$projet" "$date" "$code" "$date" "$id"
    } > "$rapport" || echo "Motif d'arrêt : rapport minimal non écrit ($rapport)."
    [ -z "$motif" ] || echo "ARRÊT : $motif à $heure (rapport absent : rapport minimal créé)"
    return 0
  fi
  [ -n "$motif" ] || return 0                       # fin normale : rapport inchangé
  IFS= read -r ligne1 < "$rapport" || :
  ligne1="${ligne1%$'\r'}"
  if [[ $ligne1 =~ $re ]]; then
    statut="${BASH_REMATCH[1]}"; statut="${statut%"${statut##*[![:space:]]}"}"
    case "$(printf '%s' "$statut" | tr 'A-Z' 'a-z')" in   # casse ignorée (É reste É : d'où Échec*)
      partiel*|echec*|échec*|Échec*) ;;             # gardé tel quel
      "") ligne1="STATUT: partiel" ;;
      *) ligne1="STATUT: partiel (l'agent avait écrit « $statut »)" ;;
    esac
    debut=2
  else
    ligne1="STATUT: partiel"                        # pas de ligne STATUT : ajoutée, rien n'est retiré
  fi
  tmp=$(mktemp "${TMPDIR:-/tmp}/motif-arret.XXXXXX") || { echo "Motif d'arrêt : rapport non annoté ($rapport)."; return 0; }
  if { printf '%s\nARRÊT : %s à %s\n' "$ligne1" "$motif" "$heure"; tail -n +"$debut" "$rapport"; } > "$tmp" \
    && cat "$tmp" > "$rapport"; then
    echo "ARRÊT : $motif à $heure (ajouté en 2e ligne du rapport)"
  else
    echo "Motif d'arrêt : rapport non annoté ($rapport)."
  fi
  rm -f "$tmp"
}
if ! annoter_arret "$CODE" "$LOGS/$DATE-round-$ID.log" "$RAPPORT" "$ID" "$PROJET" "$DATE"; then
  echo "Motif d'arrêt : annotation du rapport impossible (voir ci-dessus)."
fi

commit_wip "$ID" "$DATE" "$RAPPORT"

# --- 7. Push + PR en brouillon ---------------------------------------------
if [ "$PUSH_BRANCHES" = "oui" ]; then
  if git push -u origin "$BRANCHE"; then
    if [ "$OUVRIR_PR" = "oui" ]; then
      PR_OUVERTE=$(gh pr list --head "$BRANCHE" --state open --json number --jq '.[].number') || PR_OUVERTE=""
      PR_OUVERTE="${PR_OUVERTE%%$'\n'*}"
      if [ -z "$PR_OUVERTE" ]; then
        gh pr create --draft --base "$BRANCHE_BASE" --head "$BRANCHE" \
          --title "[claude] $BRANCHE" --body-file "$RAPPORT" || echo "Création de la PR échouée"
      elif [ "${REPRISE:-}" = 1 ]; then
        # Après une reprise (limite de session ou hebdomadaire) : la description de la PR brouillon, écrite au
        # premier push avec le rapport d'alors, reprend le rapport final.
        gh pr edit "$PR_OUVERTE" --body-file "$RAPPORT" || echo "Mise à jour de la PR échouée"
      fi
    fi
  else
    echo "Push échoué (voir ci-dessus)"
  fi
fi
echo "=== Fin du round $ID ==="
