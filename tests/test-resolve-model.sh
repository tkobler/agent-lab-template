#!/usr/bin/env bash
# Teste scripts/resolve-model.sh : le cerveau (modèle) est un réglage à trois niveaux,
# priorité agent > projet > lab. Usage : test-resolve-model.sh   Code de sortie : 0 = tous passent.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(dirname "$ICI")/scripts/resolve-model.sh"
unset MODELE_LAB ANTHROPIC_MODEL      # le défaut du lab ne doit venir que de --lab dans ces tests
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-modele.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0
egal() {  # <nom> <attendu> <obtenu>
  if [ "$2" = "$3" ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1 : attendu « $2 », obtenu « $3 »"; fi
}
agent() {  # <fichier> <ligne model ou vide> : crée un agent minimal
  { echo "---"; echo "name: essai"; [ -z "$2" ] || echo "$2"; echo "tools: Read"; echo "---"; echo "Corps."; } > "$TMP/$1"
}
resoudre() { bash "$SCRIPT" "$@" 2>/dev/null; }

agent a-opus.md "model: opus"
agent a-herite.md "model: inherit"
agent a-sans.md ""
agent a-guillemets.md 'model: "haiku"'
agent a-dangereux.md 'model: sonnet; rm -rf /'
printf -- '---\r\nname: crlf\r\nmodel: opus\r\n---\r\nCorps\r\n' > "$TMP/a-crlf.md"
printf -- '---\nname: tard\n---\nmodel: opus\n' > "$TMP/a-corps.md"      # « model: » dans le corps : ignoré
printf 'pas de front matter\nmodel: opus\n' > "$TMP/a-nu.md"

echo "== priorité agent > projet > lab"
egal "agent seul" "opus" "$(resoudre --agent "$TMP/a-opus.md")"
egal "agent + projet + lab : l'agent gagne" "opus" "$(resoudre --agent "$TMP/a-opus.md" --project haiku --lab sonnet)"
egal "agent sans model : le projet gagne" "haiku" "$(resoudre --agent "$TMP/a-sans.md" --project haiku --lab sonnet)"
egal "agent inherit : le projet gagne" "haiku" "$(resoudre --agent "$TMP/a-herite.md" --project haiku --lab sonnet)"
egal "pas d'agent, projet : le projet gagne" "haiku" "$(resoudre --project haiku --lab sonnet)"
egal "projet vide : le lab" "sonnet" "$(resoudre --agent "$TMP/a-herite.md" --project '' --lab sonnet)"
egal "lab seul" "sonnet" "$(resoudre --lab sonnet)"

echo "== cas limites"
resoudre >/dev/null; egal "aucun niveau défini : code 1" "1" "$?"
egal "aucun niveau défini : rien d'affiché" "" "$(resoudre)"
egal "fichier d'agent absent : on passe au niveau suivant" "sonnet" "$(resoudre --agent "$TMP/nexiste-pas.md" --lab sonnet)"
egal "guillemets retirés" "haiku" "$(resoudre --agent "$TMP/a-guillemets.md")"
egal "fins de ligne CRLF" "opus" "$(resoudre --agent "$TMP/a-crlf.md")"
egal "« model: » dans le corps ignoré" "sonnet" "$(resoudre --agent "$TMP/a-corps.md" --lab sonnet)"
egal "fichier sans front matter ignoré" "sonnet" "$(resoudre --agent "$TMP/a-nu.md" --lab sonnet)"
egal "valeur dangereuse refusée, niveau suivant" "sonnet" "$(resoudre --agent "$TMP/a-dangereux.md" --lab sonnet)"
egal "valeur de projet dangereuse refusée" "sonnet" "$(resoudre --project 'x$(id)' --lab sonnet)"
egal "valeur avec suffixe de contexte acceptée" "opus[1m]" "$(resoudre --lab 'opus[1m]')"
egal "identifiant complet de modèle accepté" "claude-sonnet-5-5" "$(resoudre --lab claude-sonnet-5-5)"
resoudre --lab '' --project '' >/dev/null; egal "tout vide : code 1" "1" "$?"

echo "== niveau retenu (--source)"
egal "source agent" "opus	agent" "$(resoudre --source --agent "$TMP/a-opus.md" --project haiku --lab sonnet)"
egal "source projet" "haiku	projet" "$(resoudre --source --agent "$TMP/a-sans.md" --project haiku --lab sonnet)"
egal "source lab" "sonnet	lab" "$(resoudre --source --lab sonnet)"

echo "== extrait réel d'un agent du lab"
egal "agent réel (model: sonnet) gagne sur le lab" "sonnet" "$(resoudre --agent "$ICI/fixtures/agents/chercheur-extrait-reel.md" --lab opus)"
egal "agent de base du dépôt (inherit) : le lab décide" "opus" "$(resoudre --agent "$(dirname "$ICI")/agents/chercheur.md" --lab opus)"

echo "== utilisation comme bibliothèque (source)"
SOURCEE="$(bash -c 'source "$1"; resoudre_modele "$2" "haiku" "sonnet"' _ "$SCRIPT" "$TMP/a-opus.md" 2>/dev/null)"
egal "resoudre_modele après source" "opus" "$SOURCEE"

echo "== option inconnue"
resoudre --nimporte-quoi >/dev/null; egal "option inconnue : code 2" "2" "$?"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
