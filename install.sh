#!/usr/bin/env bash
# Usage : install.sh [--root D] [--worktrees D] [--projects D] [--brew-bin D] [--prefix P] [--lock F]
# Modèle « le lab tourne dans le clone du dépôt » : install.sh s'exécute DANS le clone et ne copie rien ailleurs.
# Il n'écrit que des fichiers propres à cette machine, tous ignorés par git (voir .gitignore) :
#   - .claude/ : généré depuis claude/ (réglages de permissions et skills du manageur), marqueurs @…@ remplacés ;
#   - launchagents/ : modèles de LaunchAgents (templates/*.plist.template) rendus ; il NE les installe PAS
#     (pas de launchctl, rien dans ~/Library) : la commande de chargement est affichée, à lancer par l'utilisateur ;
#   - config.env : créé à partir de config.example.env (jamais écrasé s'il existe) ;
#   - data/ (projects, worktrees, logs) : dossiers de travail vides ; .review-done.
# Il crée aussi, seulement s'ils manquent (fichiers suivis par git, jamais écrasés) : config/TASKS.md, config/NOW.md,
# memory/Home.md et memory/lab/lab-{Project,Log,Decisions,Agent-Knowledge,Running,Team}.md (et le dossier reports/, vide).
# Les fichiers suivis par git (scripts, CLAUDE.md, agents…) ne sont JAMAIS modifiés : aucun chemin propre à la machine n'y figure.
# Réglages (défauts) : --root = le lab lui-même (portée de lecture des permissions) ; --worktrees = <lab>/data/worktrees ;
#   --projects = <lab>/data/projects ; (logs : <lab>/data/logs, écrit dans config.env sous LOGS) ;
#   --brew-bin = dossier de la commande brew si elle existe, sinon /usr/local/bin ;
#   --prefix = com.agent-lab (préfixe des étiquettes launchd : <préfixe>.night, .morning, .morning-retry, .manager, .now) ;
#   --lock = verrou des rounds (chemin absolu d'un fichier, défaut /tmp/agent-lab-round.lock, ou VERROU_ROUND du
#   config.env existant) : rendu dans config.env ET dans le LaunchAgent « now » (un plist ne lit pas config.env).
# Marqueurs : @LAB@ @RACINE@ @WORKTREES@ @PROJETS@ @LOGS@ @BREW_BIN@ @PREFIXE_LAUNCHAGENT@ @VERROU_ROUND@ et leurs formes
#   « permission » @LAB_PERM@ @RACINE_PERM@ @WORKTREES_PERM@ @PROJETS_PERM@ (~/… sous le dossier personnel, sinon //chemin absolu).
set -euo pipefail
shopt -u patsub_replacement 2>/dev/null || true     # bash 5.2 : « & » ne doit pas être spécial dans les remplacements
LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # le lab = le dossier de ce script (le clone)

usage() {
  echo "Usage : install.sh [--root D] [--worktrees D] [--projects D] [--brew-bin D] [--prefix P] [--lock F]" >&2
  echo "        (installation en place uniquement : lancez install.sh depuis le clone du dépôt, pas de dossier cible)" >&2
  exit 2
}
RACINE=""; WORKTREES=""; PROJETS=""; BREW_BIN=""; PREFIXE="com.agent-lab"; VERROU=""
while [ $# -gt 0 ]; do
  case "$1" in
    --lock) VERROU="${2:?valeur manquante}"; shift 2 ;;
    --root) RACINE="${2:?valeur manquante}"; shift 2 ;;
    --worktrees) WORKTREES="${2:?valeur manquante}"; shift 2 ;;
    --projects) PROJETS="${2:?valeur manquante}"; shift 2 ;;
    --brew-bin) BREW_BIN="${2:?valeur manquante}"; shift 2 ;;
    --prefix) PREFIXE="${2:?valeur manquante}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$RACINE" ] || RACINE="$LAB"
LOGS="$LAB/data/logs"
[ -n "$WORKTREES" ] || WORKTREES="$LAB/data/worktrees"
[ -n "$PROJETS" ] || PROJETS="$LAB/data/projects"
if [ -z "$BREW_BIN" ]; then
  if command -v brew >/dev/null 2>&1; then BREW_BIN="$(dirname "$(command -v brew)")"; else BREW_BIN="/usr/local/bin"; fi
fi

# Verrou des rounds : --lock, sinon la valeur du config.env déjà installé (réinstallation : le plist suit config.env,
# qui n'est jamais réécrit), sinon le défaut.
VERROU_DEFAUT="/tmp/agent-lab-round.lock"
VERROU_CONFIG=""
if [ -f "$LAB/config.env" ]; then
  # Lecture sans exécution : une affectation VERROU_ROUND="valeur" sans $ ni ` ni \ (sinon ignorée).
  while IFS= read -r ligne || [ -n "$ligne" ]; do
    if [[ "$ligne" =~ ^VERROU_ROUND=\"([^\"\$\`\\]*)\" ]]; then VERROU_CONFIG="${BASH_REMATCH[1]}"; fi
  done < "$LAB/config.env"
fi
if [ -z "$VERROU" ]; then VERROU="${VERROU_CONFIG:-$VERROU_DEFAUT}"; fi

# Les valeurs finissent entre guillemets dans config.env (lu par source) : aucun caractère qui y exécuterait quoi que ce soit.
for v in "$LAB" "$RACINE" "$WORKTREES" "$PROJETS" "$LOGS" "$BREW_BIN" "$PREFIXE" "$VERROU"; do
  case "$v" in
    *'"'*|*"'"*|*'$'*|*'`'*|*'\'*|*'<'*|*'&'*|*$'\n'*|*'@'*) echo "ERREUR : valeur refusée (caractère \" ' \$ \` \\ < & @ ou retour à la ligne) : $v" >&2; exit 1 ;;
  esac
done
case "$VERROU" in
  /*) ;;
  *) echo "ERREUR : --lock doit être un chemin absolu : $VERROU" >&2; exit 1 ;;
esac

# Chemin d'un dossier sous forme de motif de permission de Claude Code : ~/… sous le dossier personnel, sinon //chemin.
motif_chemin() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '/%s' "$1" ;; esac; }

rendre() {  # <fichier> : remplace les marqueurs dans le fichier (texte) par les réglages
  local c
  c="$(cat "$1")"
  c="${c//@LAB_PERM@/$(motif_chemin "$LAB")}"
  c="${c//@RACINE_PERM@/$(motif_chemin "$RACINE")}"
  c="${c//@WORKTREES_PERM@/$(motif_chemin "$WORKTREES")}"
  c="${c//@PROJETS_PERM@/$(motif_chemin "$PROJETS")}"
  c="${c//@LAB@/$LAB}"
  c="${c//@RACINE@/$RACINE}"
  c="${c//@WORKTREES@/$WORKTREES}"
  c="${c//@PROJETS@/$PROJETS}"
  c="${c//@LOGS@/$LOGS}"
  c="${c//@BREW_BIN@/$BREW_BIN}"
  c="${c//@PREFIXE_LAUNCHAGENT@/$PREFIXE}"
  c="${c//@VERROU_ROUND@/$VERROU}"
  printf '%s\n' "$c" > "$1"
}

if [ ! -f "$LAB/claude/settings.json" ]; then
  echo "ERREUR : claude/settings.json manque dans le dépôt : le manageur de ce lab n'aurait aucune permission définie." >&2
  exit 1
fi
if [ ! -f "$LAB/config.example.env" ]; then
  echo "ERREUR : config.example.env manque dans le dépôt." >&2
  exit 1
fi
echo "Installation du lab en place dans $LAB"
echo "  racine=$RACINE  worktrees=$WORKTREES  projets=$PROJETS  logs=$LOGS  brew=$BREW_BIN  prefixe=$PREFIXE  verrou=$VERROU"
# Le plist « now » et config.env doivent porter le même verrou ; config.env existant n'est jamais réécrit.
if [ -n "$VERROU_CONFIG" ] && [ "$VERROU_CONFIG" != "$VERROU" ]; then
  echo "ATTENTION : VERROU_ROUND de config.env ($VERROU_CONFIG) diffère du verrou du LaunchAgent now ($VERROU) : config.env est conservé, alignez-le à la main (sinon deux verrous différents)."
fi
[ -d "$(dirname "$VERROU")" ] || echo "ATTENTION : dossier du verrou inexistant ($(dirname "$VERROU")) : flock n'y créera pas le fichier."

# --- 1. .claude/ généré depuis claude/ (sans point : l'écriture sous .claude/ est refusée aux agents), réécrit à chaque installation
mkdir -p "$LAB/.claude"
cp -R "$LAB/claude/." "$LAB/.claude/"
while IFS= read -r -d '' f; do rendre "$f"; done < <(find "$LAB/.claude" -type f -print0)

# --- 2. Configuration locale (jamais écrasée)
if [ -f "$LAB/config.env" ]; then
  echo "  config.env existe déjà : conservé tel quel."
else
  cp "$LAB/config.example.env" "$LAB/config.env"
  rendre "$LAB/config.env"
  echo "  config.env créé (à relire : modèles, horaires)."
fi

# --- 3. Dossiers de travail (ignorés par git) et gabarits manquants (jamais écrasés)
mkdir -p "$LAB/config/projects" "$LAB/memory/lab" "$LAB/reports" "$LOGS" "$LAB/launchagents" "$WORKTREES" "$PROJETS"
[ -f "$LAB/config/TASKS.md" ] || cp "$LAB/templates/TASKS.empty.md" "$LAB/config/TASKS.md"
[ -f "$LAB/config/NOW.md" ] || cp "$LAB/templates/NOW.empty.md" "$LAB/config/NOW.md"
# Repère de la dernière revue des rapports (lu par morning-retry.sh, touché par la skill morning-review)
[ -e "$LAB/.review-done" ] || : > "$LAB/.review-done"
# Mémoire : Home.md et les notes du projet « lab » (le lab lui-même), <projet> remplacé par lab ; jamais écrasées
[ -f "$LAB/memory/Home.md" ] || cp "$LAB/templates/note-Home.empty.md" "$LAB/memory/Home.md"
for n in Project Log Decisions Agent-Knowledge Running Team; do
  if [ ! -f "$LAB/memory/lab/lab-$n.md" ]; then
    sed 's/<projet>/lab/g' "$LAB/templates/note-$n.empty.md" > "$LAB/memory/lab/lab-$n.md"
  fi
done

# --- 4. Modèles de LaunchAgents rendus (écrits dans launchagents/, pas installés)
NB_PLIST=0
for modele in "$LAB"/templates/*.plist.template; do
  [ -f "$modele" ] || continue
  nom="$(basename "$modele" .plist.template)"
  cp "$modele" "$LAB/launchagents/$PREFIXE.$nom.plist"
  rendre "$LAB/launchagents/$PREFIXE.$nom.plist"
  NB_PLIST=$((NB_PLIST + 1))
done

# --- 5. Droits d'exécution, dépôt git (si le dossier n'en est pas un), contrôle des marqueurs oubliés
chmod +x "$LAB"/scripts/*.sh
[ -d "$LAB/.git" ] || git -C "$LAB" init -q
RESTE="$(grep -rlE '@[A-Z][A-Z_]*@' "$LAB/.claude" "$LAB/config.env" "$LAB/launchagents" 2>/dev/null || true)"
if [ -n "$RESTE" ]; then
  echo "ERREUR : marqueur @…@ non remplacé dans :" >&2
  echo "$RESTE" >&2
  exit 1
fi

echo "Lab installé. $NB_PLIST modèle(s) de LaunchAgent rendu(s) dans $LAB/launchagents/ (non chargés)."
echo "Pour en charger un (action de votre part) : cp <fichier> ~/Library/LaunchAgents/ puis launchctl bootstrap gui/\$(id -u) <fichier>"
echo "Contrôle : $LAB/scripts/night.sh 1 --check"

# --- 6. Autorisations des agents : chaque fiche qui déclare COMMANDES_TEST est contrôlée (à blanc, sans claude).
# Une commande de test non couverte par les permissions du round, ou bloquée par un interdit, donne
# « PERMISSION MANQUANTE : <commande> » et fait échouer l'installation (qui, elle, est terminée à ce stade).
# Sans fiche portant la clé, rien n'est lancé.
if grep -qs '^COMMANDES_TEST=' "$LAB"/config/projects/*.env; then
  echo "Contrôle des commandes de test déclarées par les fiches (night.sh fiches) :"
  if ! bash "$LAB/scripts/night.sh" fiches; then
    echo "ERREUR : autorisations des agents incomplètes (voir PERMISSION MANQUANTE ci-dessus). Corrigez la fiche (OUTILS_EXTRA, COMMANDES_TEST) puis relancez install.sh." >&2
    exit 1
  fi
fi
