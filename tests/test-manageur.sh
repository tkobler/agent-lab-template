#!/usr/bin/env bash
# Teste CLAUDE.md (rôle du manageur), prompts/ et agents/ :
#   - aucun ancien chemin ni ancien nom (dossiers de données, fichiers de mémoire, repères, skills, signaux) ;
#   - CLAUDE.md : nouvelle carte (memory/, Decisions, Log, Project « Où en est-on », Agent-Knowledge, lab-Running,
#     .review-done), 7 skills installées, début d'échange = lire lab-Agent-Knowledge, règles strictes présentes ;
#   - prompts/night.md : lecture d'abord de <p>-Agent-Knowledge, jamais d'écriture dans memory/, section « Pièges / à savoir » ;
#   - agents/ : mêmes règles (memory/ en lecture seule), front matter cohérent.
# Usage : test-manageur.sh        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
source "$ICI/anciens-noms.sh"
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
# agents/ : seulement les agents généraux (agents/*.md) ; agents/<projet>/ (agents propres à un projet, nommés
# d'après lui) n'est pas contrôlé ici.
CIBLES=("$SQ/CLAUDE.md" "$SQ/prompts" "$SQ"/agents/*.md)
trouve() { grep -rnE -- "$1" "${CIBLES[@]}" 2>/dev/null; }
a() {  # <fichier relatif> <motif fixe> : le fichier contient ce texte
  grep -qF -- "$2" "$SQ/$1" 2>/dev/null; echo $?
}
tous_agents_contiennent() {  # <motif fixe> <agents...>
  local m="$1" n; shift
  for n in "$@"; do grep -qF -- "$m" "$SQ/agents/$n.md" || { echo 1; return; }; done
  echo 0
}

echo "== anciens chemins et noms absents de CLAUDE.md, prompts/, agents/"
ANCIEN="memo""ire/|su""ivi/|${AN_FICHES}/|${AN_TASKS_UP}|${AN_NOW_UP}|nu""it\.sh"
verifier "grep des anciens motifs du critère de fin vide" "$([ -z "$(trouve "$ANCIEN")" ]; echo $?)"
for mot in "$AN_ETAT" "$AN_A_DECIDER" "$AN_EN_SERVICE" "$AN_REVUE_FAITE" "$AN_NUIT_EN_COURS" "$AN_ROUND_NOW" \
           "$AN_SK_REVUE" "$AN_SK_PLANIFIER" "$AN_SK_LANCER" "$AN_SK_AJOUTER" "$AN_SK_SESSION" "$AN_SK_CREER" "$AN_SK_DIAG" \
           "${AN_RAPPORTS}/" "${AN_MODELES}/" "$AN_TACHES" "$AN_PROMPT" "$AN_NUIT_SH" "$AN_RUNNOW_SH" "$AN_MATIN_SH"; do
  verifier "aucune occurrence de l'ancien nom « $mot »" "$([ -z "$(trouve "$mot")" ]; echo $?)"
done
verifier "aucun chemin de machine ni dossier personnel" "$([ -z "$(trouve "~/c[l]aude-h[q]|/Us""ers/|/ho""me/")" ]; echo $?)"

echo "== CLAUDE.md : carte des fichiers et correspondance"
for m in "memory/<projet>/<projet>-Decisions.md" "memory/<projet>/<projet>-Log.md" "memory/<projet>/<projet>-Project.md" \
         "Où en est-on" "memory/<projet>/<projet>-Agent-Knowledge.md" "memory/lab/lab-Agent-Knowledge.md" \
         "memory/lab/lab-Running.md" ".review-done" ".night-running" ".now-running" "reports/AAAA-MM-JJ" \
         "agents/*.md" "agents/<projet>/*.md" "tasks-night.md" "tasks-now-" "config/TASKS.md" "config/NOW.md" "config/projects/" "templates/TASKS.empty.md"; do
  verifier "CLAUDE.md cite « $m »" "$(a CLAUDE.md "$m")"
done
for s in morning-review plan-night run-now add-project direct-session create-agent night-diagnosis; do
  verifier "CLAUDE.md cite la skill $s" "$(a CLAUDE.md "skill $s")"
  verifier "la skill $s est installée dans claude/skills/" "$([ -f "$SQ/claude/skills/$s/SKILL.md" ]; echo $?)"
done
DEBUT="$(awk '/^## Au début de chaque échange/{f=1;next} /^## /{f=0} f' "$SQ/CLAUDE.md")"
verifier "début d'échange : lire memory/lab/lab-Agent-Knowledge.md" "$(grep -qF 'memory/lab/lab-Agent-Knowledge.md' <<<"$DEBUT"; echo $?)"
verifier "début d'échange : plus d'état de travail séparé (aucune mention de « etat »)" "$(! grep -qi 'etat' <<<"$DEBUT"; echo $?)"
verifier "début d'échange : compare les rapports à .review-done" "$(grep -qF '.review-done' <<<"$DEBUT"; echo $?)"
verifier "début d'échange : .night-running bloque la modification de config/TASKS.md" "$(grep -qF '.night-running' <<<"$DEBUT"; echo $?)"

echo "== CLAUDE.md : règles strictes conservées"
for m in "Tu ne modifies jamais le code des projets" "Tu n'écris dans config/TASKS.md ou config/NOW.md qu'après ma validation explicite" \
         "Un projet par round, branches toujours en claude/<sujet-court>" "un tag d'agent existant" \
         'scripts/night.sh 1 --check' 'scripts/night.sh 2 --check' "consomme le même quota" \
         "Toute décision que je prends va dans" "gh pr list" "LaunchAgents (launchctl) sur macOS, pas cron" "Réponds en français"; do
  verifier "règle : « $m »" "$(a CLAUDE.md "$m")"
done
verifier "cycle de vie : ce qui n'est pas écrit dans memory/ est oublié" "$(a CLAUDE.md 'dans memory/ sera oublié')"

echo "== prompts/night.md"
P=prompts/night.md
verifier "le prompt existe" "$([ -f "$SQ/$P" ]; echo $?)"
verifier "lit d'abord memory/<projet>/<projet>-Agent-Knowledge.md" "$(a $P 'memory/<projet>/<projet>-Agent-Knowledge.md')"
verifier "n'écrit jamais dans memory/ (lecture seule)" "$(grep -qiE "jamais.*memory/|memory/.*lecture seule" "$SQ/$P"; echo $?)"
verifier "section « Pièges / à savoir » dans le rapport" "$(a $P '## Pièges / à savoir')"
LP="$(grep -n '## Pièges / à savoir' "$SQ/$P" | head -1 | cut -d: -f1)"
LA="$(grep -n "## Points d'attention" "$SQ/$P" | head -1 | cut -d: -f1)"
verifier "la section Pièges précède « Points d'attention »" "$([ -n "$LP" ] && [ -n "$LA" ] && [ "$LP" -lt "$LA" ]; echo $?)"
verifier "garde la ligne STATUT" "$(a $P 'STATUT: termine')"
verifier "garde l'attente des sous-agents au premier plan" "$(a $P 'au premier plan')"
verifier "garde le gabarit à reprogrammer dans config/TASKS.md" "$(a $P 'config/TASKS.md')"
verifier "transmet Agent-Knowledge aux sous-agents" "$(grep -qE 'Agent-Knowledge' "$SQ/$P" && grep -qE 'sous-agent' "$SQ/$P"; echo $?)"

echo "== agents/"
for f in "$SQ"/agents/*.md; do
  n="$(basename "$f" .md)"
  verifier "$n : front matter (name: $n, description, tools, model)" \
    "$([ "$(sed -n 1p "$f")" = '---' ] && [ "$(sed -n 2p "$f")" = "name: $n" ] && sed -n 3p "$f" | grep -q '^description: .\{20,\}' && grep -q '^tools: ' "$f" && grep -q '^model: ' "$f"; echo $?)"
  verifier "$n : memory/ en lecture seule" "$(grep -qE 'memory/.*(lecture seule|jamais)|jamais.*memory/' "$f"; echo $?)"
  verifier "$n : lit memory/<projet>/<projet>-Agent-Knowledge.md" "$(grep -qF 'memory/<projet>/<projet>-Agent-Knowledge.md' "$f"; echo $?)"
done
verifier "agents/ : aucun agent de projet à la racine (ils sont dans agents/<projet>/)" \
  "$([ "$(ls "$SQ"/agents/*.md | xargs -n1 basename | tr '\n' ' ')" = 'chercheur.md codeur.md relecteur.md testeur.md ' ]; echo $?)"
for m in "Jamais de switch, merge, rebase, push, reset --hard ni --no-verify" "Ne désactive, ne supprime et n'affaiblis jamais un test" \
         "Écris les tests AVANT le code" "Non-régression" "ce qui n'a PAS pu être testé"; do
  verifier "codeur : « $m »" "$(tous_agents_contiennent "$m" codeur)"
done
verifier "relecteur : ne modifie rien" "$(a agents/relecteur.md 'Tu ne modifies rien')"
verifier "chercheur : écrit seulement sa note dans docs/recherches/" "$(a agents/chercheur.md 'docs/recherches/')"
verifier "testeur : ne modifie pas le code du projet" "$(a agents/testeur.md 'Tu ne modifies pas le code du projet')"
verifier "codeur, testeur, chercheur : rubrique « Pièges / à savoir » dans le compte-rendu" "$(tous_agents_contiennent 'Pièges / à savoir' codeur testeur chercheur)"

echo; echo "$OK ok, $KO échec(s)"
[ "$KO" -eq 0 ]
