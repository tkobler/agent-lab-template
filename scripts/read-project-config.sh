#!/usr/bin/env bash
# À inclure (source) : lire_fiche <fichier.env>
# Lit une fiche projet SANS l'exécuter : seules les clés connues, au format CLE="valeur", sont prises.
# Une valeur ne peut contenir ni $ ni ` (sauf $HOME en tête) : une fiche modifiée ne peut pas lancer de commande.
# COMMANDES_TEST="cmd1|cmd2" : les commandes de test EXACTES du projet, séparées par | (chemins relatifs depuis la
# racine du worktree, par ex. « bash tests/lancer-tous-les-tests.sh »). night.sh --check vérifie que chacune est
# couverte par OUTILS + OUTILS_EXTRA et non interdite (voir permissions-couverture.sh) ; clé facultative.
# MODELE est le niveau « projet » du choix du cerveau (voir resolve-model.sh : agent > projet > lab).
lire_fiche() {
  local f="$1" ligne cle val n=0
  local re='^(REPO_PATH|GITHUB|BRANCHE_BASE|OUTILS_EXTRA|INTERDITS_EXTRA|COMMANDES_TEST|OUVRIR_PR|PUSH_BRANCHES|MODELE)="([^"]*)"[[:space:]]*$'
  while IFS= read -r ligne || [ -n "$ligne" ]; do
    n=$((n + 1))
    [[ "$ligne" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if [[ ! "$ligne" =~ $re ]]; then
      echo "ATTENTION : $f ligne $n ignorée (format ou clé non reconnus)" >&2
      continue
    fi
    cle="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    [[ "$val" == '$HOME'* ]] && val="$HOME${val#\$HOME}"
    if [[ "$val" == *'$'* || "$val" == *'`'* ]]; then
      echo "ATTENTION : $f ligne $n ignorée (\$ ou \` interdits dans une valeur)" >&2
      continue
    fi
    printf -v "$cle" '%s' "$val"
  done < "$f"
}
