#!/usr/bin/env bash
# Teste scripts/read-project-config.sh : lecture d'une fiche .env sans l'exécuter, clés connues seulement
# (dont MODELE, le niveau « projet » du choix du cerveau). Usage : test-read-project-config.sh
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIRE="$(dirname "$ICI")/scripts/read-project-config.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-fiche.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
OK=0; KO=0
egal() { if [ "$2" = "$3" ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1 : attendu « $2 », obtenu « $3 »"; fi; }
# lire <contenu de la fiche> <variable> : valeur de la variable après lecture dans un sous-shell propre
lire() {
  printf '%b' "$1" > "$TMP/f.env"
  bash -c 'unset REPO_PATH MODELE BRANCHE_BASE COMMANDES_TEST OUTILS_EXTRA; source "$1"; lire_fiche "$2" 2>/dev/null; printf "%s" "${!3-}"' _ "$LIRE" "$TMP/f.env" "$2"
}

echo "== clés connues"
egal "REPO_PATH lu" "/tmp/depot" "$(lire 'REPO_PATH="/tmp/depot"\n' REPO_PATH)"
egal "MODELE lu (niveau projet)" "opus" "$(lire 'MODELE="opus"\n' MODELE)"
egal "MODELE vide accepté" "" "$(lire 'MODELE=""\n' MODELE)"
egal "commentaires et lignes vides ignorés" "main" "$(lire '# note\n\nBRANCHE_BASE="main"\n' BRANCHE_BASE)"
egal "dernière ligne sans retour à la ligne" "opus" "$(lire 'MODELE="opus"' MODELE)"

echo "== COMMANDES_TEST (commandes de test exactes, séparées par |)"
egal "COMMANDES_TEST lu" "bash tests/a.sh|python3 -m unittest x" "$(lire 'COMMANDES_TEST="bash tests/a.sh|python3 -m unittest x"\n' COMMANDES_TEST)"
egal "COMMANDES_TEST vide accepté" "" "$(lire 'COMMANDES_TEST=""\n' COMMANDES_TEST)"
egal "COMMANDES_TEST absent : variable vide" "" "$(lire 'REPO_PATH="/tmp/depot"\n' COMMANDES_TEST)"
egal "COMMANDES_TEST avec \$( refusé" "" "$(lire 'COMMANDES_TEST="bash tests/$(id).sh"\n' COMMANDES_TEST)"
egal "COMMANDES_TEST avec backticks refusé" "" "$(lire 'COMMANDES_TEST="bash `id`"\n' COMMANDES_TEST)"
egal "COMMANDES_TEST sans guillemets refusé" "" "$(lire 'COMMANDES_TEST=bash tests/a.sh\n' COMMANDES_TEST)"
egal "COMMANDES_TEST lu à côté des autres clés (OUTILS_EXTRA intact)" "Bash(bash tests/*)" "$(lire 'COMMANDES_TEST="bash tests/a.sh"\nOUTILS_EXTRA="Bash(bash tests/*)"\n' OUTILS_EXTRA)"
# Extrait réel : la fiche du lab (OUTILS_EXTRA) avec la clé ajoutée
egal "fiche réelle du lab : OUTILS_EXTRA et COMMANDES_TEST lus ensemble" "bash tests/lancer-tous-les-tests.sh" "$(lire '# Le lab lui-même\nREPO_PATH="$HOME/agent-lab/data/projects/lab"\nOUTILS_EXTRA="Bash(bash tests/*),Bash(bash -n scripts/*),Bash(git mv *)"\nCOMMANDES_TEST="bash tests/lancer-tous-les-tests.sh"\nINTERDITS_EXTRA="Edit(./memory/**),Edit(./config/**)"\n' COMMANDES_TEST)"

echo "== sécurité"
egal "clé inconnue ignorée" "" "$(lire 'PATH="/evil"\nMODELE_X="a"\n' MODELE_X)"
egal "substitution de commande refusée" "" "$(lire 'MODELE="$(id)"\n' MODELE)"
egal "backticks refusés" "" "$(lire 'MODELE="`id`"\n' MODELE)"
egal "ligne sans guillemets refusée" "" "$(lire 'MODELE=opus\n' MODELE)"
egal "texte après la valeur refusé" "" "$(lire 'MODELE="opus"; touch /tmp/x\n' MODELE)"
egal "\$HOME en tête de valeur développé" "$HOME/depot" "$(lire 'REPO_PATH="$HOME/depot"\n' REPO_PATH)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
