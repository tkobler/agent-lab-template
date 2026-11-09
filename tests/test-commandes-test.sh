#!/usr/bin/env bash
# Teste COMMANDES_TEST (clé de fiche projet : commandes de test exactes, séparées par |) de bout en bout, dans un
# faux lab temporaire (night.sh refuse un LAB qui n'est pas son dossier) :
#   - night.sh <N> --check : commande couverte -> OK ; chemin absolu, ou couverte mais interdite -> « PERMISSION MANQUANTE : … »
#     et code 1 ; fiche sans la clé -> rien de changé ;
#   - un vrai round est refusé avant tout effet (claude non lancé) si une commande n'est pas couverte, et le prompt cite
#     les commandes de la fiche ;
#   - night.sh fiches : contrôle de toutes les fiches ; install.sh le lance à la fin ;
#   - night.sh --essai <projet> : courte session claude (doublé ici) avec les vraies permissions, jamais lancée par --check.
# claude / caffeinate / gtimeout sont doublés dans le HOME de substitution : aucun vrai claude, aucun push.
# Nécessite macOS (date -v dans night.sh). Usage : test-commandes-test.sh   Code 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans night.sh)."; exit 0; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/commandes-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME/.local/bin"
RACINE="$TMP/racine"; LAB="$RACINE/lab"; PROJ="$RACINE/projets/demo"
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }
dans_faux_home() { HOME="$FAUXHOME" "$@"; }

dans_faux_home bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple >/dev/null 2>&1
verifier "faux lab installé" "$([ -x "$LAB/scripts/night.sh" ]; echo $?)"
printf '\nPUSH_BRANCHES="non"\nOUVRIR_PR="non"\n' >> "$LAB/config.env"
git init -q --bare -b main "$RACINE/origine.git"
git clone -q "$RACINE/origine.git" "$PROJ" 2>/dev/null
git -C "$PROJ" -c user.name=Essai -c user.email=essai@exemple.com commit -q --allow-empty -m init
git -C "$PROJ" push -q origin main 2>/dev/null
printf '## ROUND 1\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Tâche de nuit\n' > "$LAB/config/TASKS.md"
printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/caffeinate"
printf '#!/bin/bash\nshift\nexec "$@"\n' > "$FAUXHOME/.local/bin/gtimeout"
# claude doublé : note son dossier, ses arguments (un par ligne) et chaque appel ; REPONSE_ESSAI = ce qu'il « répond »
printf '%s\n' '#!/bin/bash' \
  'echo "$PWD" > "$SORTIES_ESSAI/cwd.txt"' \
  'printf "%s\n" "$@" > "$SORTIES_ESSAI/args.txt"' \
  'echo appel >> "$SORTIES_ESSAI/appels.txt"' \
  '[ -z "${COMMANDE_WIP:-}" ] || eval "$COMMANDE_WIP"' \
  '[ -z "${REPONSE_ESSAI:-}" ] || printf "%b" "$REPONSE_ESSAI"' \
  'exit 0' > "$FAUXHOME/.local/bin/claude"
chmod +x "$FAUXHOME/.local/bin/"*
export SORTIES_ESSAI="$TMP"
NUIT="$(date -v-12H +%F)"

fiche() {  # <lignes supplémentaires> : écrit config/projects/demo.env
  printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n%b' "$PROJ" "$1" > "$LAB/config/projects/demo.env"
}
nuit() { SORTIE="$(dans_faux_home bash "$LAB/scripts/night.sh" "$@" 2>&1)"; CODE=$?; }
appels() { if [ -f "$TMP/appels.txt" ]; then wc -l < "$TMP/appels.txt" | tr -d ' '; else echo 0; fi; }

echo "== --check : commande couverte -> OK"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/lancer-tous-les-tests.sh|bash tests/faux-lab.sh"\n'
nuit 1 --check
verifier "code 0 et OK — round 1" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 1' <<<"$SORTIE"; echo $?)"
verifier "aucune PERMISSION MANQUANTE" "$(! grep -q 'PERMISSION MANQUANTE' <<<"$SORTIE"; echo $?)"
verifier "bilan : 2 commande(s) de test couverte(s)" "$(grep -q 'Commandes de test : 2 couverte(s)' <<<"$SORTIE"; echo $?)"

echo "== --check : commande en chemin absolu -> PERMISSION MANQUANTE"
fiche "OUTILS_EXTRA=\"Bash(bash tests/*)\"\nCOMMANDES_TEST=\"bash $LAB/tests/x.sh\"\n"
nuit 1 --check
verifier "code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
verifier "ligne « PERMISSION MANQUANTE : bash <chemin absolu>/tests/x.sh »" "$(grep -qxF "PERMISSION MANQUANTE : bash $LAB/tests/x.sh" <<<"$SORTIE"; echo $?)"
verifier "pas de message OK — round" "$(! grep -q 'OK — round' <<<"$SORTIE"; echo $?)"

echo "== --check : commande couverte mais interdite -> PERMISSION MANQUANTE"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nINTERDITS_EXTRA="Bash(bash tests/dangereux*)"\nCOMMANDES_TEST="bash tests/dangereux.sh"\n'
nuit 1 --check
verifier "code 1 et ligne PERMISSION MANQUANTE" "$([ "$CODE" -eq 1 ] && grep -qxF 'PERMISSION MANQUANTE : bash tests/dangereux.sh' <<<"$SORTIE"; echo $?)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/x.sh --no-verify"\n'
nuit 1 --check
verifier "interdit de base de night.sh (--no-verify) : code 1 et PERMISSION MANQUANTE" "$([ "$CODE" -eq 1 ] && grep -qxF 'PERMISSION MANQUANTE : bash tests/x.sh --no-verify' <<<"$SORTIE"; echo $?)"

echo "== --check : une couverte, une manquante -> seule la manquante est nommée"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh|npm test"\n'
nuit 1 --check
verifier "code 1, « npm test » nommée, « bash tests/a.sh » non" "$([ "$CODE" -eq 1 ] && grep -qxF 'PERMISSION MANQUANTE : npm test' <<<"$SORTIE" && ! grep -qF 'PERMISSION MANQUANTE : bash tests/a.sh' <<<"$SORTIE"; echo $?)"

echo "== --check : fiche sans la clé -> rien de changé"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\n'
nuit 1 --check
verifier "code 0 et OK — round 1" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 1' <<<"$SORTIE"; echo $?)"
verifier "aucune mention des commandes de test ni de PERMISSION MANQUANTE" "$(! grep -qE 'Commandes de test|PERMISSION MANQUANTE' <<<"$SORTIE"; echo $?)"
fiche 'COMMANDES_TEST=""\n'
nuit 1 --check
verifier "clé vide : comme sans clé (code 0, aucune mention)" "$([ "$CODE" -eq 0 ] && ! grep -qE 'Commandes de test|PERMISSION MANQUANTE' <<<"$SORTIE"; echo $?)"
verifier "--check n'a lancé aucun claude et n'a rien écrit dans reports/ ni data/logs/" "$([ "$(appels)" = 0 ] && [ -z "$(ls -A "$LAB/reports")$(ls -A "$LAB/data/logs")" ]; echo $?)"

echo "== vrai round : refusé avant tout effet si une commande n'est pas couverte"
fiche "OUTILS_EXTRA=\"Bash(bash tests/*)\"\nCOMMANDES_TEST=\"bash $LAB/tests/x.sh\"\n"
nuit 1
verifier "code 1, claude non lancé" "$([ "$CODE" -eq 1 ] && [ "$(appels)" = 0 ]; echo $?)"
verifier "rapport d'échec écrit (STATUT: echec)" "$(head -1 "$LAB/reports/$NUIT/round-1-demo.md" 2>/dev/null | grep -q 'STATUT: echec'; echo $?)"
verifier "aucun worktree préparé" "$([ ! -e "$LAB/data/worktrees/demo" ]; echo $?)"
rm -f "$LAB/reports/$NUIT/round-1-demo.md"

echo "== vrai round : le prompt cite les commandes de la fiche, telles quelles, en chemin relatif"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/lancer-tous-les-tests.sh|bash tests/faux-lab.sh"\n'
nuit 1
verifier "code 0, claude lancé une fois" "$([ "$CODE" -eq 0 ] && [ "$(appels)" = 1 ]; echo $?)"
verifier "prompt : commande 1 sur sa ligne" "$(grep -qxF -- '- bash tests/lancer-tous-les-tests.sh' "$TMP/args.txt"; echo $?)"
verifier "prompt : commande 2 sur sa ligne" "$(grep -qxF -- '- bash tests/faux-lab.sh' "$TMP/args.txt"; echo $?)"
verifier "prompt : consigne (telles quelles, chemin relatif)" "$(grep -q 'TELLES QUELLES' "$TMP/args.txt" && grep -q 'chemin relatif' "$TMP/args.txt"; echo $?)"
verifier "claude lancé dans le worktree du projet" "$([ "$(cat "$TMP/cwd.txt")" = "$LAB/data/worktrees/demo" ]; echo $?)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\n'
nuit 1
verifier "sans la clé : le prompt ne parle pas de commandes de test" "$([ "$CODE" -eq 0 ] && ! grep -q 'Commandes de test du projet (fiche' "$TMP/args.txt"; echo $?)"

echo "== night.sh fiches : contrôle de toutes les fiches"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh"\n'
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$PROJ" > "$LAB/config/projects/autre.env"
nuit fiches
verifier "toutes couvertes (et une fiche sans clé) : code 0, aucune PERMISSION MANQUANTE" "$([ "$CODE" -eq 0 ] && ! grep -q 'PERMISSION MANQUANTE' <<<"$SORTIE"; echo $?)"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\nCOMMANDES_TEST="bash tests/a.sh"\n' "$PROJ" > "$LAB/config/projects/autre.env"
nuit fiches
verifier "fiche « autre » sans OUTILS_EXTRA : code 1, commande nommée, fiche nommée" "$([ "$CODE" -eq 1 ] && grep -qxF 'PERMISSION MANQUANTE : bash tests/a.sh' <<<"$SORTIE" && grep -q 'autre' <<<"$SORTIE"; echo $?)"
nuit fiches --check
verifier "night.sh fiches --check accepté (même contrôle)" "$([ "$CODE" -eq 1 ]; echo $?)"
rm -f "$LAB/config/projects/autre.env"

echo "== install.sh : lance le contrôle des fiches à la fin"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh"\n'
SORTIE="$(dans_faux_home bash "$LAB/install.sh" --brew-bin /usr/bin 2>&1)"; CODE=$?
verifier "tout couvert : réinstallation code 0, contrôle annoncé" "$([ "$CODE" -eq 0 ] && grep -q 'Contrôle des commandes de test' <<<"$SORTIE"; echo $?)"
fiche "OUTILS_EXTRA=\"Bash(bash tests/*)\"\nCOMMANDES_TEST=\"bash $LAB/tests/a.sh\"\n"
SORTIE="$(dans_faux_home bash "$LAB/install.sh" --brew-bin /usr/bin 2>&1)"; CODE=$?
verifier "commande en chemin absolu : code 1 et PERMISSION MANQUANTE" "$([ "$CODE" -eq 1 ] && grep -qxF "PERMISSION MANQUANTE : bash $LAB/tests/a.sh" <<<"$SORTIE"; echo $?)"
verifier "l'installation elle-même est faite avant (message « Lab installé »)" "$(grep -q 'Lab installé' <<<"$SORTIE"; echo $?)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\n'
SORTIE="$(dans_faux_home bash "$LAB/install.sh" --brew-bin /usr/bin 2>&1)"; CODE=$?
verifier "aucune fiche avec la clé : code 0, aucun contrôle lancé" "$([ "$CODE" -eq 0 ] && ! grep -qE 'Contrôle des commandes de test|PERMISSION MANQUANTE' <<<"$SORTIE"; echo $?)"

echo "== night.sh --essai <projet> : session claude avec les vraies permissions (sur demande seulement)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh|bash tests/b.sh"\n'
rm -f "$TMP/appels.txt" "$TMP/args.txt" "$TMP/cwd.txt"
REPONSE_ESSAI='OK : bash tests/a.sh\nREFUSÉE : bash tests/b.sh\n' nuit --essai demo
verifier "une commande refusée : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
verifier "…listée « PERMISSION MANQUANTE : bash tests/b.sh »" "$(grep -qxF 'PERMISSION MANQUANTE : bash tests/b.sh' <<<"$SORTIE"; echo $?)"
verifier "…la commande acceptée n'est pas signalée" "$(! grep -qF 'PERMISSION MANQUANTE : bash tests/a.sh' <<<"$SORTIE"; echo $?)"
verifier "claude lancé une fois, en mode -p, dans le worktree du projet" "$([ "$(appels)" = 1 ] && [ "$(head -1 "$TMP/args.txt")" = -p ] && [ "$(cat "$TMP/cwd.txt")" = "$LAB/data/worktrees/demo" ]; echo $?)"
verifier "vraies permissions : --allowedTools avec Bash(bash tests/*), --disallowedTools avec Bash(git push*)" \
  "$(grep -qxF -- '--allowedTools' "$TMP/args.txt" && grep -qF 'Bash(bash tests/*)' "$TMP/args.txt" && grep -qxF -- '--disallowedTools' "$TMP/args.txt" && grep -qF 'Bash(git push*)' "$TMP/args.txt"; echo $?)"
verifier "prompt : les deux commandes et la consigne de ne rien contourner" "$(grep -qxF -- '- bash tests/a.sh' "$TMP/args.txt" && grep -qxF -- '- bash tests/b.sh' "$TMP/args.txt" && grep -q 'contourn' "$TMP/args.txt"; echo $?)"
verifier "rien écrit dans reports/ (pas de rapport d'essai)" "$([ -z "$(find "$LAB/reports" -name '*essai*')" ]; echo $?)"
REPONSE_ESSAI='OK : bash tests/a.sh\nOK : bash tests/b.sh\n' nuit --essai demo
verifier "tout accepté : code 0, aucune PERMISSION MANQUANTE" "$([ "$CODE" -eq 0 ] && ! grep -q 'PERMISSION MANQUANTE' <<<"$SORTIE"; echo $?)"
fiche "OUTILS_EXTRA=\"Bash(bash tests/*)\"\nCOMMANDES_TEST=\"bash $LAB/tests/a.sh\"\n"
rm -f "$TMP/appels.txt"
REPONSE_ESSAI='OK : x\n' nuit --essai demo
verifier "contrôle statique d'abord : chemin absolu signalé même si claude répond OK" "$([ "$CODE" -eq 1 ] && grep -qxF "PERMISSION MANQUANTE : bash $LAB/tests/a.sh" <<<"$SORTIE"; echo $?)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\n'
rm -f "$TMP/appels.txt"
nuit --essai demo
verifier "fiche sans la clé : message, code 0, claude non lancé" "$([ "$CODE" -eq 0 ] && grep -q 'COMMANDES_TEST' <<<"$SORTIE" && [ "$(appels)" = 0 ]; echo $?)"
nuit --essai
verifier "sans projet : code non nul, claude non lancé" "$([ "$CODE" -ne 0 ] && [ "$(appels)" = 0 ]; echo $?)"
nuit --essai inconnu
verifier "projet inconnu : code 1, claude non lancé" "$([ "$CODE" -eq 1 ] && grep -q 'Projet inconnu' <<<"$SORTIE" && [ "$(appels)" = 0 ]; echo $?)"
nuit --essai demo --check
verifier "--essai et --check ne se combinent pas : code 2, claude non lancé" "$([ "$CODE" -eq 2 ] && [ "$(appels)" = 0 ]; echo $?)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh"\n'
rm -rf "$LAB/data/worktrees/demo"
nuit --essai demo
verifier "worktree absent : code 1, message, claude non lancé" "$([ "$CODE" -eq 1 ] && grep -q 'Worktree absent' <<<"$SORTIE" && [ "$(appels)" = 0 ]; echo $?)"

echo "== --essai : durcissement (OK en nombre suffisant, pas d'Edit/Write, nom de projet filtré)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh|bash tests/b.sh"\n'
mkdir -p "$LAB/data/worktrees/demo"
rm -f "$TMP/appels.txt" "$TMP/args.txt"
REPONSE_ESSAI='OK : bash tests/a.sh\n' nuit --essai demo
verifier "1 ligne OK pour 2 commandes, sans REFUSÉE : code 1 et message" "$([ "$CODE" -eq 1 ] && grep -q 'ERREUR' <<<"$SORTIE" && grep -q "1 ligne" <<<"$SORTIE"; echo $?)"
REPONSE_ESSAI='' nuit --essai demo
verifier "sortie vide de claude : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
REPONSE_ESSAI='OK : bash tests/a.sh\nOK : bash tests/b.sh\nOK : en trop\n' nuit --essai demo
verifier "plus de lignes OK que de commandes : accepté (code 0)" "$([ "$CODE" -eq 0 ]; echo $?)"
REPONSE_ESSAI='texte OK : pas en début de ligne\nOK : bash tests/b.sh\n' nuit --essai demo
verifier "« OK : » doit commencer la ligne : 1 seule ligne valide pour 2 commandes, code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*),Edit(src/**),Write(docs/**)"\nCOMMANDES_TEST="bash tests/a.sh"\n'
REPONSE_ESSAI='OK : bash tests/a.sh\n' nuit --essai demo
ALLOWED="$(grep -A1 -xF -- '--allowedTools' "$TMP/args.txt" | tail -1)"
verifier "essai : --allowedTools sans Edit ni Write (même ceux de OUTILS_EXTRA), mais avec Read et Bash(bash tests/*)" \
  "$([ -n "$ALLOWED" ] && ! grep -qE '(^|,)(Edit|Write|MultiEdit|NotebookEdit)(\(|,|$)' <<<"$ALLOWED" && grep -qE '(^|,)Read(,|$)' <<<"$ALLOWED" && grep -qF 'Bash(bash tests/*)' <<<"$ALLOWED"; echo $?)"
DISALLOWED="$(grep -A1 -xF -- '--disallowedTools' "$TMP/args.txt" | tail -1)"
verifier "essai : les interdits restent entiers (Edit(…/scripts/**) du lab, Edit(~/.ssh/**), Bash(git push*))" "$(grep -qE 'Edit\([^)]*/scripts/\*\*\)' <<<"$DISALLOWED" && grep -qF 'Edit(~/.ssh/**)' <<<"$DISALLOWED" && grep -qF 'Bash(git push*)' <<<"$DISALLOWED"; echo $?)"
verifier "essai : Edit, Write, MultiEdit et NotebookEdit (sans argument) sont aussi interdits" \
  "$(grep -qE '(^|,)Edit(,|$)' <<<"$DISALLOWED" && grep -qE '(^|,)Write(,|$)' <<<"$DISALLOWED" && grep -qE '(^|,)MultiEdit(,|$)' <<<"$DISALLOWED" && grep -qE '(^|,)NotebookEdit(,|$)' <<<"$DISALLOWED"; echo $?)"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh"\n'
rm -f "$TMP/appels.txt"
for MAUVAIS in '../x' 'a/b' 'a b' '-x' 'a;b' '.'; do
  nuit --essai "$MAUVAIS"
  verifier "nom de projet « $MAUVAIS » refusé : code 2, message, claude non lancé" "$([ "$CODE" -eq 2 ] && grep -q 'Nom de projet' <<<"$SORTIE" && [ "$(appels)" = 0 ]; echo $?)"
done
printf '## ROUND 1\nprojet: ../evil\nbranche: claude/essai\n\n- [codeur] Tâche\n' > "$LAB/config/TASKS.md"
nuit 1 --check
verifier "tâches : PROJET « ../evil » refusé en --check (code non nul, message)" "$([ "$CODE" -ne 0 ] && grep -q 'Nom de projet' <<<"$SORTIE"; echo $?)"
nuit 1
verifier "tâches : PROJET « ../evil » refusé en vrai round, claude non lancé, rapport d'échec sous « inconnu » (pas de chemin piégé)" \
  "$([ "$CODE" -ne 0 ] && [ "$(appels)" = 0 ] && [ -f "$LAB/reports/$NUIT/round-1-inconnu.md" ] && [ ! -e "$LAB/reports/$NUIT/round-1-../evil.md" ]; echo $?)"
rm -f "$LAB/reports/$NUIT/round-1-inconnu.md"
printf '## ROUND 1\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Tâche de nuit\n' > "$LAB/config/TASKS.md"
nuit 1 --check
verifier "nom valide (demo) : toujours accepté" "$([ "$CODE" -eq 0 ]; echo $?)"

echo "== night.sh fiches : verifier_permissions appelé par fiche"
fiche 'OUTILS_EXTRA="Bash(bash tests/*)"\nCOMMANDES_TEST="bash tests/a.sh"\n'
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\nOUTILS_EXTRA="Bash(*)"\nCOMMANDES_TEST="bash tests/a.sh"\n' "$PROJ" > "$LAB/config/projects/large.env"
nuit fiches
verifier "fiche « large » (Bash(*) autorisé, pourtant commande couverte) : code 1, PERMISSIONS affiché, fiche nommée" \
  "$([ "$CODE" -eq 1 ] && grep -q 'PERMISSIONS : ' <<<"$SORTIE" && grep -q 'large' <<<"$SORTIE" && ! grep -q 'PERMISSION MANQUANTE' <<<"$SORTIE"; echo $?)"
verifier "…la fiche saine « demo » n'est pas marquée KO" "$(grep -qE 'demo : 1 commande\(s\) de test couverte' <<<"$SORTIE"; echo $?)"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\nOUTILS_EXTRA="Bash(bash tests/*),Foo"\nCOMMANDES_TEST="bash tests/a.sh"\n' "$PROJ" > "$LAB/config/projects/large.env"
nuit fiches
verifier "fiche avec outil inconnu : code 1" "$([ "$CODE" -eq 1 ] && grep -q 'outil inconnu' <<<"$SORTIE"; echo $?)"
rm -f "$LAB/config/projects/large.env"
nuit fiches
verifier "sans la fiche fautive : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"

echo "== commit wip : le mode 755 de l'index est conservé"
export GIT_AUTHOR_NAME=Essai GIT_AUTHOR_EMAIL=essai@exemple.com GIT_COMMITTER_NAME=Essai GIT_COMMITTER_EMAIL=essai@exemple.com
PROJW="$RACINE/projets/wip"
git init -q --bare -b main "$RACINE/origine-wip.git"
git clone -q "$RACINE/origine-wip.git" "$PROJW" 2>/dev/null
mkdir -p "$PROJW/scripts"
printf '#!/bin/bash\necho a\n' > "$PROJW/scripts/a.sh"; printf '#!/bin/bash\necho b\n' > "$PROJW/scripts/b.sh"
printf '#!/bin/bash\necho c\n' > "$PROJW/scripts/c.sh"; printf 'texte\n' > "$PROJW/notes.txt"
git -C "$PROJW" add --chmod=+x scripts/a.sh
git -C "$PROJW" add scripts/b.sh scripts/c.sh notes.txt
git -C "$PROJW" commit -q -m init
git -C "$PROJW" push -q origin main 2>/dev/null
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$PROJW" > "$LAB/config/projects/wip.env"
printf '## ROUND 1\nprojet: wip\nbranche: claude/wip-mode\n\n- [codeur] Tâche\n' > "$LAB/config/TASKS.md"
# a.sh : 755 dans HEAD, contenu modifié et 644 sur disque ; b.sh : 644 dans HEAD, passé en 755 dans l'index
# (git add --chmod=+x), contenu modifié, 644 sur disque ; c.sh : 644 partout, modifié ; notes.txt : modifié
COMMANDE_WIP='echo "# modif" >> scripts/a.sh; chmod 644 scripts/a.sh; echo "# modif" >> scripts/b.sh; git add --chmod=+x scripts/b.sh; chmod 644 scripts/b.sh; echo "# modif" >> scripts/c.sh; echo plus >> notes.txt' nuit 1
WTW="$LAB/data/worktrees/wip"
verifier "round réel : code 0, commit wip fait" "$([ "$CODE" -eq 0 ] && [ "$(git -C "$WTW" log -1 --format=%s)" = "wip(claude): état en fin de round 1 ($NUIT)" ]; echo $?)"
verifier "a.sh : 100755 dans HEAD (755 de HEAD conservé)" "$(git -C "$WTW" ls-tree HEAD scripts/a.sh | grep -q '^100755 '; echo $?)"
verifier "b.sh : 100755 dans HEAD (755 de l'index conservé)" "$(git -C "$WTW" ls-tree HEAD scripts/b.sh | grep -q '^100755 '; echo $?)"
verifier "c.sh : reste 100644 (pas de 755 inventé)" "$(git -C "$WTW" ls-tree HEAD scripts/c.sh | grep -q '^100644 '; echo $?)"
verifier "contenus bien commités (a, b, c, notes)" "$(git -C "$WTW" show HEAD:scripts/a.sh | grep -q modif && git -C "$WTW" show HEAD:scripts/b.sh | grep -q modif && git -C "$WTW" show HEAD:scripts/c.sh | grep -q modif && git -C "$WTW" show HEAD:notes.txt | grep -q plus; echo $?)"
verifier "copie de travail propre après le commit" "$([ -z "$(git -C "$WTW" status --porcelain)" ]; echo $?)"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

echo "== documentation : prompt du chef de nuit et skill add-project"
SQ="$(dirname "$ICI")"
verifier "prompts/night.md : tests lancés avec les commandes de la fiche, telles quelles, en chemin relatif depuis la racine du worktree" \
  "$(grep -q 'COMMANDES_TEST' "$SQ/prompts/night.md" && grep -qi 'telles quelles' "$SQ/prompts/night.md" && grep -q 'chemin relatif' "$SQ/prompts/night.md" && grep -q 'racine du worktree' "$SQ/prompts/night.md"; echo $?)"
verifier "prompts/night.md : une commande de test refusée est notée, jamais contournée par un chemin absolu" "$(grep -q 'chemin absolu' "$SQ/prompts/night.md"; echo $?)"
verifier "skill add-project : la fiche .env déclare COMMANDES_TEST (chemin relatif) et l'essai --essai est mentionné" \
  "$(grep -q 'COMMANDES_TEST=' "$SQ/claude/skills/add-project/SKILL.md" && grep -q 'night.sh --essai' "$SQ/claude/skills/add-project/SKILL.md" && grep -q 'chemin relatif' "$SQ/claude/skills/add-project/SKILL.md"; echo $?)"
verifier "skill add-project : le contrôle night.sh fiches / install.sh est expliqué" "$(grep -q 'night.sh fiches' "$SQ/claude/skills/add-project/SKILL.md"; echo $?)"
verifier "read-project-config.sh documente COMMANDES_TEST" "$(grep -q '^# COMMANDES_TEST=' "$SQ/scripts/read-project-config.sh"; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
