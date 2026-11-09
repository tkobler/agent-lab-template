#!/usr/bin/env bash
# Teste scripts/export-lab.sh : liste blanche, dossiers de données exclus, contrôle anti-données perso
# bloquant, sortie jamais écrasée, installation du lab dans un faux lab. Rien n'est publié, aucun dépôt créé.
# Le dépôt réel n'est jamais modifié : les cas d'échec travaillent sur une COPIE du dépôt (--source).
# Usage : test-export-lab.sh        Code de sortie : 0 = tous les tests passent.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
BUILD="$SQ/scripts/export-lab.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-export-lab.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME"
OK=0; KO=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
absent() { [ ! -e "$1" ]; echo $?; }
present() { [ -e "$1" ]; echo $?; }

# Copie du dépôt (sans .git) à compléter de fichiers « perso » ; PERSO-MARQUEUR sert à vérifier qu'il ne sort pas.
copie_source() {  # <dossier destination>
  mkdir -p "$1"
  ( cd "$SQ" && tar --exclude=.git -cf - . ) | ( cd "$1" && tar -xf - )
}

echo "== script présent, usage"
verifier "scripts/export-lab.sh existe" "$(present "$BUILD")"
bash "$BUILD" >/dev/null 2>&1; CODE=$?
verifier "sans argument : code 2 (usage)" "$([ "$CODE" -eq 2 ]; echo $?)"

echo "== génération sur une copie contenant des fichiers perso dans des dossiers exclus"
SRC="$TMP/src"; copie_source "$SRC"
for d in memory config reports logs projects worktrees; do
  mkdir -p "$SRC/$d/sous"
  echo "PERSO-MARQUEUR" > "$SRC/$d/perso.md"
  echo "PERSO-MARQUEUR" > "$SRC/$d/sous/profond.md"
done
mkdir -p "$SRC/tools"; echo "PERSO-MARQUEUR" > "$SRC/tools/non-liste.txt"      # hors liste blanche explicite
echo "PERSO-MARQUEUR" > "$SRC/fichier-racine-inconnu.md"                        # hors liste blanche
mkdir -p "$SRC/.git"; echo x > "$SRC/.git/config"
OUT="$TMP/sortie"
SORTIE="$(HOME="$FAUXHOME" bash "$BUILD" "$OUT" --source "$SRC" 2>&1)"; CODE=$?
echo "$SORTIE" | sed 's/^/    | /'
verifier "code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
for d in memory config reports logs projects worktrees; do
  verifier "dossier exclu absent de la sortie : $d/" "$(absent "$OUT/$d")"
done
verifier "aucun fichier de la sortie ne contient le marqueur perso" "$(! grep -rqF PERSO-MARQUEUR --exclude=test-export-lab.sh "$OUT"; echo $?)"
verifier "fichier racine hors liste blanche absent" "$(absent "$OUT/fichier-racine-inconnu.md")"
verifier "tools/non-liste.txt (hors liste blanche) absent" "$(absent "$OUT/tools/non-liste.txt")"
verifier "pas de .git dans la sortie" "$(absent "$OUT/.git")"
verifier "tools/ ne contient que la liste blanche (4 fichiers)" "$([ "$(find "$OUT/tools" -type f ! -name '*.pyc' | wc -l | tr -d ' ')" -eq 4 ]; echo $?)"
for p in install.sh README.md CLAUDE.md config.example.env .gitignore scripts/night.sh scripts/export-lab.sh agents/codeur.md \
         prompts/night.md templates/TASKS.empty.md claude/settings.json claude/skills/run-now/SKILL.md \
         tests/lancer-tous-les-tests.sh tests/controle-donnees-perso.sh tests/test-export-lab.sh; do
  verifier "présent : $p" "$(present "$OUT/$p")"
done
echo "== tools/ : liste blanche explicite (outil généralisé + son test + __init__.py), le reste est exclu"
for p in tools/__init__.py tools/agent_knowledge.py tools/test_agent_knowledge.py tools/test_agents_round.py; do
  verifier "livré : $p" "$(present "$OUT/$p")"
done
for p in tools/test_agent_knowledge_coffre.py tools/controle_coffre.py tools/migrer_decisions.py tools/test_migrer_decisions.py tools/test_controle_coffre.py tools/test_depot.py; do
  verifier "exclu : $p" "$(absent "$OUT/$p")"
done
verifier "les tests Python livrés passent dans le lab exporté (sans coffre, sans .git)" "$(cd "$OUT" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest >/dev/null 2>&1; echo $?)"
verifier "agent_knowledge.py sans coffre : code 1 (aucun projet), pas de crash" "$(cd "$OUT" && PYTHONDONTWRITEBYTECODE=1 python3 tools/agent_knowledge.py >/dev/null 2>&1; [ $? -eq 1 ]; echo $?)"
verifier "le contrôle anti-données perso passe sur la sortie" "$(bash "$OUT/tests/controle-donnees-perso.sh" "$OUT" >/dev/null 2>&1; echo $?)"
echo "== agents de projet (agents/<projet>/) : jamais exportés, seuls les agents généraux le sont"
mkdir -p "$SRC/agents/un-projet/profond"
echo "PERSO-MARQUEUR" > "$SRC/agents/un-projet/agent-de-projet.md"
echo "PERSO-MARQUEUR" > "$SRC/agents/un-projet/profond/autre.md"
OUTA="$TMP/sortie-agents"
SORTIE="$(HOME="$FAUXHOME" bash "$BUILD" "$OUTA" --source "$SRC" 2>&1)"; CODE=$?
verifier "source avec agents de projet (marqueur perso compris) : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "aucun sous-dossier dans agents/ de la sortie" "$([ -z "$(find "$OUTA/agents" -mindepth 1 -type d)" ]; echo $?)"
verifier "agents/un-projet/ absent de la sortie" "$(absent "$OUTA/agents/un-projet")"
verifier "aucun fichier de la sortie ne contient le marqueur perso (agents de projet compris)" "$(! grep -rqF PERSO-MARQUEUR --exclude=test-export-lab.sh "$OUTA"; echo $?)"
verifier "les 4 agents généraux sont exportés" "$(for n in chercheur codeur relecteur testeur; do [ -f "$OUTA/agents/$n.md" ] || exit 1; done; echo $?)"
verifier "agents/ de la sortie : uniquement des fichiers .md à la racine" "$([ -z "$(find "$OUTA/agents" -mindepth 1 ! -name '*.md')" ] && [ "$(find "$OUTA/agents" -type f | wc -l | tr -d ' ')" -eq "$(find "$OUTA/agents" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ')" ]; echo $?)"
verifier "le dépôt source n'est pas modifié (agents/un-projet/ toujours là)" "$([ -f "$SRC/agents/un-projet/agent-de-projet.md" ]; echo $?)"
echo "== export sans aucun agent de projet"
SRCB="$TMP/src-sans-projet"; copie_source "$SRCB"
find "$SRCB/agents" -mindepth 1 -type d -exec rm -rf {} +
OUTB="$TMP/sortie-sans-projet"
HOME="$FAUXHOME" bash "$BUILD" "$OUTB" --source "$SRCB" >/dev/null 2>&1; CODE=$?
verifier "source sans sous-dossier dans agents/ : code 0 et 4 agents exportés" "$([ "$CODE" -eq 0 ] && [ "$(find "$OUTB/agents" -type f | wc -l | tr -d ' ')" -eq 4 ]; echo $?)"

echo "== donnée perso dans un fichier autorisé : échec, rien n'est laissé en sortie"
SRC2="$TMP/src2"; copie_source "$SRC2"
CHEMIN_MAC="/Us""ers/quelquun/doc"                # assemblé : ce fichier ne doit pas se reconnaître lui-même
printf 'voir %s\n' "$CHEMIN_MAC" >> "$SRC2/agents/codeur.md"
OUT2="$TMP/sortie2"
SORTIE="$(HOME="$FAUXHOME" bash "$BUILD" "$OUT2" --source "$SRC2" 2>&1)"; CODE=$?
verifier "code non nul" "$([ "$CODE" -ne 0 ]; echo $?)"
verifier "message d'échec du contrôle" "$(grep -q 'ECHEC' <<<"$SORTIE"; echo $?)"
verifier "la sortie ne recopie pas le contenu trouvé" "$(! grep -qF "$CHEMIN_MAC" <<<"$SORTIE"; echo $?)"
verifier "dossier de sortie non créé" "$(absent "$OUT2")"

echo "== adresse e-mail dans scripts/night.sh (autorisé) : échec aussi"
SRC3="$TMP/src3"; copie_source "$SRC3"
ADRESSE="moi""@vraie-adresse.org"                 # assemblée, comme ci-dessus
printf '# contact: %s\n' "$ADRESSE" >>"$SRC3/scripts/night.sh"
SORTIE="$(HOME="$FAUXHOME" bash "$BUILD" "$TMP/sortie3" --source "$SRC3" 2>&1)"; CODE=$?
verifier "code non nul" "$([ "$CODE" -ne 0 ]; echo $?)"
verifier "dossier de sortie non créé" "$(absent "$TMP/sortie3")"

echo "== sortie jamais écrasée"
mkdir -p "$TMP/occupe"; echo garde > "$TMP/occupe/important.txt"
HOME="$FAUXHOME" bash "$BUILD" "$TMP/occupe" --source "$SRC" >/dev/null 2>&1; CODE=$?
verifier "dossier non vide refusé (code non nul)" "$([ "$CODE" -ne 0 ]; echo $?)"
verifier "contenu existant intact" "$(grep -q garde "$TMP/occupe/important.txt"; echo $?)"
mkdir -p "$TMP/vide"
HOME="$FAUXHOME" bash "$BUILD" "$TMP/vide" --source "$SRC" >/dev/null 2>&1; CODE=$?
verifier "dossier existant mais vide accepté" "$([ "$CODE" -eq 0 ] && [ -f "$TMP/vide/install.sh" ]; echo $?)"
HOME="$FAUXHOME" bash "$BUILD" "$SRC/dedans" --source "$SRC" >/dev/null 2>&1; CODE=$?
verifier "sortie à l'intérieur de la source refusée" "$([ "$CODE" -ne 0 ]; echo $?)"
HOME="$FAUXHOME" bash "$BUILD" "$TMP/x" --source "$TMP/inexistante" >/dev/null 2>&1; CODE=$?
verifier "source inexistante : code non nul" "$([ "$CODE" -ne 0 ]; echo $?)"

echo "== lien symbolique dans la liste blanche : refusé"
SRC4="$TMP/src4"; copie_source "$SRC4"
ln -s /etc/hosts "$SRC4/agents/lien.md"
HOME="$FAUXHOME" bash "$BUILD" "$TMP/sortie4" --source "$SRC4" >/dev/null 2>&1; CODE=$?
verifier "code non nul et rien créé" "$([ "$CODE" -ne 0 ] && [ ! -e "$TMP/sortie4" ]; echo $?)"

echo "== aucun git push / dépôt créé"
verifier "export-lab.sh ne contient ni push ni remote ni init ni gh" "$(! grep -qE '^[^#]*(git[^|;&]*(push|remote|init)|gh +(repo|pr)|--no-verify)' "$BUILD"; echo $?)"
verifier "pas de .git dans la sortie générée" "$(absent "$OUT/.git")"

echo "== installation du lab généré dans un faux lab"
RACINE="$TMP/racine"; LAB="$RACINE/lab"
SORTIE="$(HOME="$FAUXHOME" SOURCE_DEPOT="$OUT" bash "$OUT/tests/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple 2>&1)"; CODE=$?
verifier "install.sh du lab : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "night.sh exécutable dans le faux lab" "$([ -x "$LAB/scripts/night.sh" ]; echo $?)"
verifier "config.env, config/TASKS.md, .claude/settings.json créés" "$([ -f "$LAB/config.env" ] && [ -f "$LAB/config/TASKS.md" ] && [ -f "$LAB/.claude/settings.json" ]; echo $?)"
verifier "7 skills installées" "$([ "$(find "$LAB/.claude/skills" -name SKILL.md | wc -l | tr -d ' ')" -eq 7 ]; echo $?)"
HOME="$FAUXHOME" bash "$LAB/scripts/night.sh" 1 --check >/dev/null 2>&1; CODE=$?
verifier "night.sh 1 --check s'exécute (code 0 ou 1 : tâches vides, pas de crash)" "$([ "$CODE" -le 1 ]; echo $?)"
verifier "launchagents rendus mais rien dans le vrai ~/Library" "$([ -f "$LAB/launchagents/com.exemple.night.plist" ] && [ ! -e "$FAUXHOME/Library/LaunchAgents" ]; echo $?)"

echo "== liste des fichiers générés"
( cd "$OUT" && find . -type f ! -path './tests/fixtures/*' | sort | sed 's/^\.\//    /' )
echo "    (+ $(find "$OUT/tests/fixtures" -type f | wc -l | tr -d ' ') fichier(s) dans tests/fixtures/)"

# La suite livrée dans le lab doit passer dans le lab (garde contre la récursion : la suite relance ce test).
if [ -z "${TEST_LAB_IMBRIQUE:-}" ]; then
  echo "== suite de tests du lab, lancée dans le lab généré"
  SUITE="$(TEST_LAB_IMBRIQUE=1 HOME="$FAUXHOME" bash "$OUT/tests/lancer-tous-les-tests.sh" 2>&1)"; CODE=$?
  grep -E '^(###|-->|TOUT PASSE|[0-9]+ étape)' <<<"$SUITE" | sed 's/^/    | /'
  verifier "suite du lab : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
fi

echo
echo "$OK ok, $KO échec(s)"
[ "$KO" -eq 0 ]
