#!/usr/bin/env bash
# Teste scripts/permissions-couverture.sh : une commande est-elle couverte par les permissions d'un round
# (OUTILS + OUTILS_EXTRA) sans être bloquée par un interdit ? Le motif Bash(préfixe*) est une glob sur la commande
# ENTIÈRE, comme dans Claude Code ; un interdit l'emporte toujours.
# Fonctions pures : aucun faux lab ni claude. Usage : test-permissions-couverture.sh   Code 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$(dirname "$ICI")/scripts/permissions-couverture.sh"
OK=0; KO=0
egal() { if [ "$2" = "$3" ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1 : attendu « $2 », obtenu « $3 »"; fi; }
if [ ! -f "$LIB" ]; then echo "  ECHEC $LIB absent"; echo "Résultat : 0 réussi(s), 1 échec(s)"; exit 1; fi
source "$LIB"

# code <commande...> : code de retour, sans sortie
code() { "$@" >/dev/null 2>&1; echo $?; }

echo "== motif_couvre : glob sur la commande entière"
egal "bash tests/* couvre bash tests/x.sh" 0 "$(code motif_couvre 'bash tests/*' 'bash tests/x.sh')"
egal "bash tests/* couvre bash tests/ (joker vide)" 0 "$(code motif_couvre 'bash tests/*' 'bash tests/')"
egal "bash tests/* ne couvre pas bash tests (sans barre)" 1 "$(code motif_couvre 'bash tests/*' 'bash tests')"
egal "chemin absolu non couvert par bash tests/*" 1 "$(code motif_couvre 'bash tests/*' 'bash /srv/lab/tests/x.sh')"
egal "préfixe différent non couvert" 1 "$(code motif_couvre 'bash tests/*' 'sh tests/x.sh')"
egal "sans joker : commande identique couverte" 0 "$(code motif_couvre 'git --version' 'git --version')"
egal "sans joker : commande plus longue non couverte" 1 "$(code motif_couvre 'git --version' 'git --version --build')"
egal "joker au milieu : *--no-verify* couvre git commit --no-verify -m x" 0 "$(code motif_couvre '*--no-verify*' 'git commit --no-verify -m x')"
egal "joker au milieu : git commit *-n couvre git commit -m x -n" 0 "$(code motif_couvre 'git commit * -n' 'git commit -m x -n')"
egal "joker au milieu : git commit * -n ne couvre pas git commit -m x" 1 "$(code motif_couvre 'git commit * -n' 'git commit -m x')"
egal "git status* couvre git status" 0 "$(code motif_couvre 'git status*' 'git status')"
egal "« ? » est un caractère ordinaire, pas un joker" 1 "$(code motif_couvre 'bash tests/?.sh' 'bash tests/a.sh')"
egal "« ? » littéral couvert par lui-même" 0 "$(code motif_couvre 'bash tests/?.sh' 'bash tests/?.sh')"
egal "« [ab] » est un texte, pas une classe" 1 "$(code motif_couvre 'echo [ab]' 'echo a')"
egal "« [ab] » littéral couvert par lui-même" 0 "$(code motif_couvre 'echo [ab]' 'echo [ab]')"
egal "forme préfixe python3 -m unittest * couvre python3 -m unittest tools.test_x" 0 "$(code motif_couvre 'python3 -m unittest *' 'python3 -m unittest tools.test_x')"
egal "forme :* couvre la commande seule" 0 "$(code motif_couvre 'npm run test:*' 'npm run test')"
egal "forme :* couvre la commande avec arguments" 0 "$(code motif_couvre 'npm run test:*' 'npm run test -- --watch')"
egal "forme :* ne couvre pas un mot plus long" 1 "$(code motif_couvre 'npm run test:*' 'npm run tester')"
egal "commande vide jamais couverte" 1 "$(code motif_couvre 'bash tests/*' '')"
egal "motif vide ne couvre rien" 1 "$(code motif_couvre '' 'bash tests/x.sh')"

echo "== commande_permise : 0 couverte, 1 non couverte, 2 interdite, 3 composée"
OUT="Read,Glob,Edit,Bash(git status*),Bash(bash tests/*),Bash(python3 -m unittest *)"
INT="Bash(git push*),Bash(*--no-verify*),Edit(./memory/**)"
egal "couverte -> 0" 0 "$(code commande_permise 'bash tests/x.sh' "$OUT" "$INT")"
egal "chemin absolu -> 1" 1 "$(code commande_permise 'bash /srv/lab/tests/x.sh' "$OUT" "$INT")"
egal "commande inconnue -> 1" 1 "$(code commande_permise 'npm test' "$OUT" "$INT")"
egal "couverte mais interdite (*--no-verify*) -> 2" 2 "$(code commande_permise 'bash tests/x.sh --no-verify' "$OUT" "$INT")"
egal "l'interdit l'emporte même s'il est listé avant" 2 "$(code commande_permise 'bash tests/x.sh --no-verify' "$OUT" "Bash(*--no-verify*)")"
egal "outil non Bash dans les autorisés ignoré (Read ne couvre pas une commande)" 1 "$(code commande_permise 'ls' "Read,Glob" "")"
egal "interdit d'un autre outil (Edit) sans effet" 0 "$(code commande_permise 'bash tests/x.sh' "$OUT" "Edit(./memory/**)")"
egal "interdits vides -> couverte" 0 "$(code commande_permise 'bash tests/x.sh' "$OUT" "")"
egal "autorisés vides -> non couverte" 1 "$(code commande_permise 'bash tests/x.sh' "" "$INT")"
egal "Bash seul interdit tout" 2 "$(code commande_permise 'bash tests/x.sh' "$OUT" "Bash")"
egal "Bash(*) interdit tout" 2 "$(code commande_permise 'bash tests/x.sh' "$OUT" "Bash(*)")"
egal "composée avec && -> 3" 3 "$(code commande_permise 'bash tests/a.sh && rm -f x' "$OUT" "$INT")"
egal "composée avec ; -> 3" 3 "$(code commande_permise 'bash tests/a.sh; bash tests/b.sh' "$OUT" "$INT")"
egal "composée avec || -> 3" 3 "$(code commande_permise 'bash tests/a.sh || true' "$OUT" "$INT")"
egal "substitution \$( -> 3" 3 "$(code commande_permise 'bash tests/$(id).sh' "$OUT" "$INT")"
egal "backtick -> 3" 3 "$(code commande_permise 'bash tests/`id`.sh' "$OUT" "$INT")"
egal "redirection > -> 3" 3 "$(code commande_permise 'bash tests/a.sh > /etc/x' "$OUT" "$INT")"
egal "retour à la ligne -> 3" 3 "$(code commande_permise $'bash tests/a.sh\nrm x' "$OUT" "$INT")"

echo "== commandes_manquantes : sortie « PERMISSION MANQUANTE : <commande> » et code"
sortie="$(commandes_manquantes 'bash tests/a.sh|bash tests/b.sh' "$OUT" "$INT")"; c=$?
egal "toutes couvertes : code 0" 0 "$c"
egal "toutes couvertes : sans PERMISSION MANQUANTE" 0 "$(! grep -q 'PERMISSION MANQUANTE' <<<"$sortie"; echo $?)"
sortie="$(commandes_manquantes 'bash tests/a.sh|bash /srv/lab/tests/b.sh' "$OUT" "$INT")"; c=$?
egal "une chemin absolu : code 1" 1 "$c"
egal "…ligne exacte PERMISSION MANQUANTE : <commande>" 1 "$(grep -cxF 'PERMISSION MANQUANTE : bash /srv/lab/tests/b.sh' <<<"$sortie")"
egal "…la commande couverte n'est pas signalée" 0 "$(grep -cF 'PERMISSION MANQUANTE : bash tests/a.sh' <<<"$sortie")"
sortie="$(commandes_manquantes 'bash tests/a.sh --no-verify' "$OUT" "$INT")"; c=$?
egal "couverte mais interdite : code 1" 1 "$c"
egal "…ligne PERMISSION MANQUANTE" 1 "$(grep -cxF 'PERMISSION MANQUANTE : bash tests/a.sh --no-verify' <<<"$sortie")"
egal "…raison : interdit" 1 "$(grep -c 'interdit' <<<"$sortie")"
sortie="$(commandes_manquantes 'bash tests/a.sh && rm x' "$OUT" "$INT")"; c=$?
egal "composée : code 1 et PERMISSION MANQUANTE" 0 "$([ "$c" -eq 1 ] && grep -qxF 'PERMISSION MANQUANTE : bash tests/a.sh && rm x' <<<"$sortie"; echo $?)"
sortie="$(commandes_manquantes '  bash tests/a.sh  |  npm test ' "$OUT" "$INT")"; c=$?
egal "espaces autour des | retirés, 2e commande manquante" 1 "$(grep -cxF 'PERMISSION MANQUANTE : npm test' <<<"$sortie")"
sortie="$(commandes_manquantes 'bash tests/a.sh||bash tests/b.sh|' "$OUT" "$INT")"; c=$?
egal "entrées vides ignorées : code 0" 0 "$c"
sortie="$(commandes_manquantes '' "$OUT" "$INT")"; c=$?
egal "clé vide : code 0, aucune sortie" 0 "$([ "$c" -eq 0 ] && [ -z "$sortie" ]; echo $?)"
sortie="$(commandes_manquantes 'npm test|make|bash /srv/x.sh' "$OUT" "$INT")"
egal "plusieurs manquantes : toutes listées" 3 "$(grep -c '^PERMISSION MANQUANTE : ' <<<"$sortie")"

echo "== extrait réel : OUTILS_EXTRA de la fiche du lab, commandes de test du lab"
# OUTILS_EXTRA de la fiche projet lab (valeur réelle), et les listes de base de night.sh recopiées
REEL_EXTRA="Bash(bash tests/*),Bash(bash -n scripts/*),Bash(bash -n tests/*),Bash(bash -n install.sh),Bash(python3 tools/*),Bash(python3 -m unittest *),Bash(mktemp -d /tmp/*),Bash(git mv *)"
REEL_OUT="Read,Glob,Grep,Edit,Write,TodoWrite,Task,Agent,WebSearch,WebFetch,Bash(git status*),Bash(git diff*),Bash(git log*),Bash(git show*),Bash(git add *),Bash(git commit *),Bash(ls *),Bash(git --version),$REEL_EXTRA"
REEL_INT="Bash(git push*),Bash(git switch*),Bash(git checkout*),Bash(git merge*),Bash(git rebase*),Bash(git reset --hard*),Bash(*--no-verify*),Bash(rm -rf*),Bash(sudo *),Bash(gh *),Bash(git -C *),Bash(git commit -n*),Bash(git commit * -n),Edit(./memory/**),Edit(./config/**)"
egal "suite complète du lab couverte" 0 "$(code commande_permise 'bash tests/lancer-tous-les-tests.sh' "$REEL_OUT" "$REEL_INT")"
egal "bash tests/faux-lab.sh couverte" 0 "$(code commande_permise 'bash tests/faux-lab.sh' "$REEL_OUT" "$REEL_INT")"
egal "python3 -m unittest couverte (avec argument)" 0 "$(code commande_permise 'python3 -m unittest tools.test_agent_knowledge' "$REEL_OUT" "$REEL_INT")"
egal "python3 -m unittest SEUL non couverte (le motif attend un espace)" 1 "$(code commande_permise 'python3 -m unittest' "$REEL_OUT" "$REEL_INT")"
egal "bash -n scripts/night.sh couverte" 0 "$(code commande_permise 'bash -n scripts/night.sh' "$REEL_OUT" "$REEL_INT")"
egal "chemin absolu de la suite : refusé le 24/10, détecté" 1 "$(code commande_permise 'bash /srv/lab/data/worktrees/lab/tests/lancer-tous-les-tests.sh' "$REEL_OUT" "$REEL_INT")"
egal "python3 /tmp/script.py : refusé le 24/10, détecté" 1 "$(code commande_permise 'python3 /tmp/script.py' "$REEL_OUT" "$REEL_INT")"
egal "git mv couverte" 0 "$(code commande_permise 'git mv a b' "$REEL_OUT" "$REEL_INT")"
egal "gh pr list : interdite par gh * (l'interdit est testé en premier)" 2 "$(code commande_permise 'gh pr list' "$REEL_OUT" "$REEL_INT")"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
