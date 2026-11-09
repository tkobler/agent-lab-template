#!/usr/bin/env bash
# Teste les noms anglais des fichiers-signaux, des archives de tâches, des identifiants de round et du prompt :
#   .night-running, .now-running, tasks-night.md, tasks-now-HHMM.md, round « now-HHMM », prompts/night.md.
# Un VRAI round est lancé (night.sh sans --check) dans un faux lab temporaire, avec des doublures de claude, caffeinate
# et gtimeout placées dans $HOME/.local/bin du HOME de substitution (night.sh les trouve en premier dans son PATH) :
# aucun vrai claude, aucun push (PUSH_BRANCHES="non"), le vrai lab et ~/Library/LaunchAgents ne sont pas touchés.
# morning.sh et run-now.sh ne sont PAS exécutés (ils pilotent tmux et launchd) : contrôle statique de leurs noms.
# Usage : test-noms-fichiers.sh        Code de sortie : 0 = tout passe. Nécessite macOS (date -v).
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
source "$ICI/anciens-noms.sh"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans night.sh)."; exit 0; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/noms-fichiers.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME/.local/bin"
RACINE="$TMP/racine"; LAB="$RACINE/lab"
OK=0; KO=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
dans_faux_home() { HOME="$FAUXHOME" "$@"; }

echo "== faux lab installé, faux projet git avec dépôt distant local"
dans_faux_home bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
verifier "install.sh : code 0" "$?"
printf '\nPUSH_BRANCHES="non"\nOUVRIR_PR="non"\n' >> "$LAB/config.env"
git init -q --bare -b main "$RACINE/origine.git"
git clone -q "$RACINE/origine.git" "$RACINE/projets/demo" 2>/dev/null
git -C "$RACINE/projets/demo" -c user.name=Essai -c user.email=essai@exemple.com commit -q --allow-empty -m init
git -C "$RACINE/projets/demo" push -q origin main 2>/dev/null
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$RACINE/projets/demo" > "$LAB/config/projects/demo.env"

# Doublures. claude note ce qu'il voit au moment où il tourne : fichiers-signaux présents, prompt système reçu.
printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/caffeinate"      # caffeinate -i <commande>...
printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/gtimeout"
printf '%s\n' '#!/bin/bash' \
  'ls -A "$LAB_ESSAI" > "$SORTIES_ESSAI/vu-par-claude.txt"' \
  'cat "$LAB_ESSAI/.now-running" > "$SORTIES_ESSAI/signal-now.txt" 2>/dev/null' \
  'while [ $# -gt 0 ]; do [ "$1" = --append-system-prompt ] && printf %s "$2" > "$SORTIES_ESSAI/prompt-systeme.txt"; shift; done' \
  'exit 0' > "$FAUXHOME/.local/bin/claude"
chmod +x "$FAUXHOME/.local/bin/"*
export LAB_ESSAI="$LAB" SORTIES_ESSAI="$TMP"

cat > "$LAB/config/TASKS.md" <<'EOF'
## ROUND 1
projet: demo
branche: claude/essai

- [codeur] Tâche de nuit
EOF
cat > "$LAB/config/NOW.md" <<'EOF'
## NOW
projet: demo
branche: claude/essai

- [codeur] Tâche immédiate
EOF

NUIT="$(date -v-12H +%F)"; JOUR="$(date +%F)"

echo "== round de nuit 1 (vrai lancement, claude doublé)"
dans_faux_home bash "$LAB/scripts/night.sh" 1 > "$TMP/sortie-nuit.txt" 2>&1; CODE=$?
verifier "night.sh 1 : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "claude a bien été lancé (doublure appelée)" "$([ -f "$TMP/vu-par-claude.txt" ]; echo $?)"
[ -f "$TMP/vu-par-claude.txt" ] || { echo "    | sortie de night.sh :"; cat "$TMP/sortie-nuit.txt" "$LAB"/data/logs/*.log 2>/dev/null | head -30 | sed 's/^/    | /'; }
verifier "pendant le round : .night-running présent" "$(grep -qx '.night-running' "$TMP/vu-par-claude.txt"; echo $?)"
verifier "archive des tâches reports/<date>/tasks-night.md" "$([ -f "$LAB/reports/$NUIT/tasks-night.md" ]; echo $?)"
verifier "l'archive contient la tâche de nuit" "$(grep -q 'Tâche de nuit' "$LAB/reports/$NUIT/tasks-night.md"; echo $?)"
verifier ".night-running laissé en place après le round (retiré par morning.sh)" "$([ -f "$LAB/.night-running" ]; echo $?)"
verifier "aucun ancien fichier-signal ni ancienne archive (nuit)" \
  "$([ ! -e "$LAB/$AN_NUIT_EN_COURS" ] && [ -z "$(ls "$LAB/reports/$NUIT" | grep "^${AN_TACHES}")" ]; echo $?)"
verifier "prompt système lu dans prompts/night.md (identique, non vide)" \
  "$([ -s "$TMP/prompt-systeme.txt" ] && [ "$(cat "$TMP/prompt-systeme.txt")" = "$(cat "$LAB/prompts/night.md")" ]; echo $?)"
verifier "prompts/night.md installé, l'ancien prompts/$AN_PROMPT absent" "$([ -f "$LAB/prompts/night.md" ] && [ ! -e "$LAB/prompts/$AN_PROMPT" ]; echo $?)"
verifier "journal du round : logs/<date>-round-1.log" "$([ -f "$LAB/data/logs/$NUIT-round-1.log" ]; echo $?)"

echo "== round immédiat (now)"
dans_faux_home bash "$LAB/scripts/night.sh" now > "$TMP/sortie-now.txt" 2>&1; CODE=$?
verifier "night.sh now : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "pendant le round : .now-running présent" "$(grep -qx '.now-running' "$TMP/vu-par-claude.txt"; echo $?)"
verifier "le signal contient « <dossier du jour> round-now-HHMM »" \
  "$(grep -Eq "^$LAB/reports/$JOUR round-now-[0-9]{4}\$" "$TMP/signal-now.txt"; echo $?)"
verifier ".now-running retiré à la fin du round" "$([ ! -e "$LAB/.now-running" ]; echo $?)"
ARCH="$(ls "$LAB/reports/$JOUR" 2>/dev/null | grep -E '^tasks-now-[0-9]{4}\.md$' | head -1)"
verifier "archive reports/<date>/tasks-now-HHMM.md" "$([ -n "$ARCH" ]; echo $?)"
verifier "l'archive contient la tâche immédiate" "$([ -n "$ARCH" ] && grep -q 'Tâche immédiate' "$LAB/reports/$JOUR/$ARCH"; echo $?)"
verifier "journal logs/<date>-round-now-HHMM.log" "$(ls "$LAB/data/logs" | grep -Eq "^$JOUR-round-now-[0-9]{4}\.log\$"; echo $?)"
verifier "config/NOW.md remis au gabarit (jamais exécuté deux fois)" "$(cmp -s "$LAB/config/NOW.md" "$LAB/templates/NOW.empty.md"; echo $?)"
verifier "aucun ancien nom d'archive ni d'identifiant (now)" \
  "$([ -z "$(ls "$LAB/reports/$JOUR" "$LAB/data/logs" | grep -E "${AN_TACHES}|${AN_ID_NOW}")" ]; echo $?)"

echo "== night.sh refuse de nouveau un round « now » dont l'identifiant est ancien"
dans_faux_home bash "$LAB/scripts/night.sh" "$AN_NOW" --check >/dev/null 2>&1
verifier "ancien nom de round refusé : code 2" "$([ "$?" -eq 2 ]; echo $?)"

echo "== morning.sh et run-now.sh (contrôle statique : non exécutés, ils pilotent tmux et launchd)"
verifier "morning.sh : retire .night-running et lit tasks-night.md" \
  "$(grep -q 'rm -f "$LAB/.night-running"' "$LAB/scripts/morning.sh" && grep -q 'tasks-night.md' "$LAB/scripts/morning.sh"; echo $?)"
verifier "run-now.sh : attend .now-running" "$(grep -q '\.now-running' "$LAB/scripts/run-now.sh"; echo $?)"
verifier "CLAUDE.md et .gitignore installés : nouveaux noms" \
  "$(grep -q '\.night-running' "$LAB/CLAUDE.md" && grep -q '\.now-running' "$LAB/CLAUDE.md" && grep -q 'tasks-night.md' "$LAB/CLAUDE.md" \
     && grep -qx '\.night-running' "$LAB/.gitignore" && grep -qx '\.now-running' "$LAB/.gitignore"; echo $?)"

echo "== aucun ancien nom dans le lab installé (hors logs et rapports de ce test)"
ANCIENS="${AN_NUIT_EN_COURS}|${AN_ROUND_NOW}|${AN_TACHES_NUIT}|${AN_TACHES}|${AN_ID_NOW}|${AN_PROMPT}"
TROUVES="$(grep -rIlE "$ANCIENS" "$LAB/scripts" "$LAB/prompts" "$LAB/templates" "$LAB"/agents/*.md "$LAB/.claude" "$LAB/CLAUDE.md" "$LAB/.gitignore" 2>/dev/null)"
verifier "scripts, prompts, templates, agents, réglages, CLAUDE.md, .gitignore : aucun ancien nom" "$([ -z "$TROUVES" ]; echo $?)"
[ -z "$TROUVES" ] || echo "$TROUVES" | sed 's/^/    | /'

echo "== partie publiable du dépôt : aucun ancien nom (hors noms de skills)"
# Le README n'a plus de table de correspondance (la table ancien -> nouveau est dans l'historique git et dans la mémoire) ;
# seul le fichier de noms assemblés fait exception ; les noms de skills (lancer-maintenant, session-directe, revue-matin…) ne sont pas des
# anciens noms de fichiers : le motif ne cherche que les noms de scripts, options, modèles, signaux, archives, prompt.
# agents/ : les agents généraux seulement (agents/*.md, ajoutés plus bas) ; agents/<projet>/ n'est pas publiable.
PUBLIABLE=(scripts prompts templates claude tests install.sh config.example.env CLAUDE.md .gitignore)   # README.md : traité à part
MOTIF="${AN_NUIT_SH}|${AN_NUIT_CHAINE_SH}|${AN_RUNNOW_SH}|${AN_MATIN_SH}|${AN_RELANCE_MATIN_SH}|${AN_DIRECTE_SH}|${AN_NUIT1}|${AN_VERIFIER}"
MOTIF="$MOTIF|${AN_PREFIXE}|${AN_PLAFOND}|${AN_PLIST_MODELE}|${AN_NUIT_EN_COURS}|${AN_ROUND_NOW}|${AN_TACHES}|${AN_ID_NOW}"
MOTIF="$MOTIF|${AN_DEPOT}|${AN_PREFIXE_DEPOT}|${AN_BUILD}|${AN_PREFIXE_INTERM}|${AN_MEM_ANCIEN}"
MOTIF="$MOTIF|prompts/${AN_PROMPT}|${AN_TASKS_UP}\.md|${AN_NOW_UP}\.md|${AN_FICHES}/|${AN_RAPPORTS}/|${AN_MODELES}/"
RESTE="$(cd "$SQ" && { awk '/<!-- correspondance:début -->/{c=1} !c{print FILENAME ":" FNR ":" $0} /<!-- correspondance:fin -->/{c=0}' README.md
  grep -rInE --exclude=anciens-noms.sh --exclude-dir=fixtures "$MOTIF" "${PUBLIABLE[@]}" agents/*.md 2>/dev/null; } \
  | grep -E "$MOTIF" | grep -v '^$' || true)"
verifier "grep des anciens noms dans la partie publiable : vide" "$([ -z "$RESTE" ]; echo $?)"
[ -z "$RESTE" ] || echo "$RESTE" | cut -c1-200 | sed 's/^/    | /'
# Cas négatif : un fichier qui contient un ancien nom (dépôt, préfixe launchd, script d'export) doit être détecté par ce motif.
NEG="$TMP/negatif"; mkdir -p "$NEG"
for ancien in "$AN_DEPOT" "$AN_PREFIXE_DEPOT" "$AN_BUILD" "$AN_PREFIXE_INTERM" "$AN_MEM_ANCIEN"; do
  printf 'voir %s\n' "$ancien" > "$NEG/fichier.md"
  verifier "cas négatif : un fichier contenant « $ancien » est détecté" "$(grep -rqE "$MOTIF" "$NEG"; echo $?)"
done
printf 'voir agent-lab, com.agent-lab, memory/lab et export-lab.sh\n' > "$NEG/fichier.md"
verifier "cas positif : les nouveaux noms ne sont pas détectés" "$(! grep -rqE "$MOTIF" "$NEG"; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
