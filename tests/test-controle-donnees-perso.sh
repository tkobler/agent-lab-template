#!/usr/bin/env bash
# Teste le contrôle controle-donnees-perso.sh lui-même : il doit échouer sur les fausses données
# (fixtures/mauvais, catégorie par catégorie et ligne par ligne), réussir sur fixtures/bon et sur la partie publiable du dépôt (memory/, config/, reports/ non contrôlés),
# trouver le compte courant et $HOME lus à l'exécution (fichiers temporaires, rien d'écrit dans le dépôt),
# et ne jamais répondre « OK » en silence (binaire, fichier illisible, dossier vide).
# Usage : test-controle-donnees-perso.sh        Code de sortie : 0 = tous les tests passent.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CTRL="$ICI/controle-donnees-perso.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-controle.XXXXXX")"
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
OK=0; KO=0
verifier() {  # <nom> <condition vraie ?> : 0 = réussi
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
lignes() {  # <sortie> <fichier> : nombre de lignes distinctes signalées dans ce fichier
  grep -o "TROUVÉ $2:[0-9]*" <<<"$1" | sort -u | wc -l | tr -d ' '
}

echo "== fixtures/mauvais : doit échouer, toutes catégories détectées"
SORTIE="$(bash "$CTRL" "$ICI/fixtures/mauvais" 2>&1)"; CODE=$?
verifier "code de sortie non nul sur les fausses données" "$([ "$CODE" -ne 0 ]; echo $?)"
for cat in CHEMIN-MAC EMAIL JETON MOT-DE-PASSE GITHUB NOM-PROJET; do
  verifier "catégorie $cat détectée" "$(grep -q "\[$cat\]" <<<"$SORTIE"; echo $?)"
done
verifier "chemins.sh : 5 lignes mauvaises trouvées" "$([ "$(lignes "$SORTIE" chemins.sh)" -eq 5 ]; echo $?)"
verifier "chemins2.txt : dossier Linux, racine root, volumes, dossier privé, Cellar, Windows, racine des comptes en fin de ligne (7 lignes)" "$([ "$(lignes "$SORTIE" chemins2.txt)" -eq 7 ]; echo $?)"
verifier "secrets2.txt : api_key:, token=, Bearer, JWT, glpat-, npm_, AIza, secret: (8 lignes)" "$([ "$(lignes "$SORTIE" secrets2.txt)" -eq 8 ]; echo $?)"
verifier "identite2.md : adresse .local, GitLab, Bitbucket, remote git@ (4 lignes)" "$([ "$(lignes "$SORTIE" identite2.md)" -eq 4 ]; echo $?)"
verifier "projets.md : noms de projets trouvés" "$([ "$(lignes "$SORTIE" projets.md)" -eq 2 ]; echo $?)"
NOMF=copie-de-projet'-factice-a.txt'      # en deux morceaux : le contrôle ne doit pas se reconnaître lui-même
verifier "nom de fichier contenant un nom de projet signalé" "$(grep -qF "TROUVÉ $NOMF [NOM-PROJET] (nom de fichier)" <<<"$SORTIE"; echo $?)"
verifier "la sortie ne recopie pas le contenu trouvé" "$(! grep -q 'FAUXFAUX' <<<"$SORTIE"; echo $?)"

echo "== vrais noms (assemblés en morceaux) : toujours signalés, dans le contenu et dans les noms de fichiers"
RN="$TMP/vrais-noms"; mkdir -p "$RN"
printf 'projet %s et %s\n' 'glidat''or2' 'dev-monke''yc' > "$RN/a.md"
printf 'agent %s, %s, %s\n' 'testeur-connect''iq' 'analyste-activi''te' 'relancer-simulat''eur.sh' > "$RN/b.md"
printf 'projet %s et plist %s\n' 'export-noti''on' 'nuit''2.plist' > "$RN/c.md"
printf 'cd ~/claude''-hq/x\nsource "$HOME/claude''-hq/y"\nok\n' > "$RN/d.sh"
SORTIE="$(bash "$CTRL" "$RN" 2>&1)"; CODE=$?
verifier "vrais noms : code de sortie non nul" "$([ "$CODE" -ne 0 ]; echo $?)"
verifier "a.md : projet et agent réels (1 ligne)" "$([ "$(lignes "$SORTIE" a.md)" -eq 1 ]; echo $?)"
verifier "b.md : agents et script réels (1 ligne)" "$([ "$(lignes "$SORTIE" b.md)" -eq 1 ]; echo $?)"
verifier "c.md : projet de notes et plist réels (1 ligne)" "$([ "$(lignes "$SORTIE" c.md)" -eq 1 ]; echo $?)"
verifier "d.sh : ancien chemin du lab, ~ et \$HOME (2 lignes, pas la 3e)" "$([ "$(lignes "$SORTIE" d.sh)" -eq 2 ]; echo $?)"
verifier "d.sh : signalé CHEMIN-MAC" "$(grep -q 'TROUVÉ d.sh:1 \[CHEMIN-MAC\]' <<<"$SORTIE"; echo $?)"
RN2="$TMP/vrais-noms-fichier"; mkdir -p "$RN2"
printf 'rien\n' > "$RN2/copie-de-glidat""or2.txt"
SORTIE="$(bash "$CTRL" "$RN2" 2>&1)"; CODE=$?
verifier "vrai nom dans un nom de fichier : signalé" "$([ "$CODE" -ne 0 ] && grep -qF 'TROUVÉ copie-de-glidat''or2.txt [NOM-PROJET] (nom de fichier)' <<<"$SORTIE"; echo $?)"

echo "== fixtures/bon : doit réussir"
bash "$CTRL" "$ICI/fixtures/bon" >/dev/null 2>&1; CODE=$?
verifier "code de sortie 0 sur le dossier propre" "$([ "$CODE" -eq 0 ]; echo $?)"

echo "== dossier de tests analysé sans argument : fixtures exclues"
bash "$CTRL" >/dev/null 2>&1; CODE=$?
verifier "la partie publiable (fixtures exclues) passe" "$([ "$CODE" -eq 0 ]; echo $?)"

echo "== sans argument : seule la partie publiable est contrôlée (dépôt factice)"
REPO="$TMP/repo"; mkdir -p "$REPO/tests" "$REPO/scripts" "$REPO/memory" "$REPO/config" "$REPO/reports"
cp "$CTRL" "$REPO/tests/controle-donnees-perso.sh"
echo 'echo propre' > "$REPO/scripts/a.sh"
cp "$ICI/fixtures/mauvais/identite.md" "$REPO/memory/note.md"
cp "$ICI/fixtures/mauvais/secrets.txt" "$REPO/config/config.env"
cp "$ICI/fixtures/mauvais/chemins.sh" "$REPO/reports/r.md"
SORTIE="$(bash "$REPO/tests/controle-donnees-perso.sh" 2>&1)"; CODE=$?
verifier "données perso dans memory/, config/, reports/ : ignorées (code 0)" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "2 fichiers analysés (scripts/a.sh et le contrôle copié)" "$(grep -q '^OK : 2 fichier' <<<"$SORTIE"; echo $?)"
cp "$ICI/fixtures/mauvais/chemins.sh" "$REPO/scripts/b.sh"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "même contenu dans scripts/ : échec" "$([ "$CODE" -eq 1 ]; echo $?)"
rm "$REPO/scripts/b.sh"
bash "$REPO/tests/controle-donnees-perso.sh" "$REPO/memory" >/dev/null 2>&1; CODE=$?
verifier "memory/ passé en argument : contrôlé, échec" "$([ "$CODE" -eq 1 ]; echo $?)"
mkdir -p "$REPO/docs/restructuration" "$REPO/docs/fiabilite"
cp "$ICI/fixtures/mauvais/identite.md" "$REPO/docs/restructuration/note.md"
cp "$ICI/fixtures/mauvais/chemins.sh" "$REPO/docs/fiabilite/note.md"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "docs/restructuration et docs/fiabilite : plus d'exclusion, contrôlés (échec)" "$([ "$CODE" -eq 1 ]; echo $?)"
rm "$REPO/docs/restructuration/note.md"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "docs/fiabilite seul : contrôlé, échec" "$([ "$CODE" -eq 1 ]; echo $?)"
rm "$REPO/docs/fiabilite/note.md"
cp "$ICI/fixtures/bon/propre.sh" "$REPO/docs/fiabilite/propre.sh"
bash "$REPO/tests/controle-donnees-perso.sh" "$REPO/docs/fiabilite" >/dev/null 2>&1; CODE=$?
verifier "docs/fiabilite propre passé en argument : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
rm "$REPO/docs/fiabilite/propre.sh"
cp "$ICI/fixtures/mauvais/identite.md" "$REPO/docs/restructuration/note.md"
bash "$REPO/tests/controle-donnees-perso.sh" "$REPO/docs/restructuration" >/dev/null 2>&1; CODE=$?
verifier "docs/restructuration passé en argument : contrôlé, échec" "$([ "$CODE" -eq 1 ]; echo $?)"
rm "$REPO/docs/restructuration/note.md"
cp "$ICI/fixtures/mauvais/chemins.sh" "$REPO/docs/guide.md"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "autre fichier de docs/ : contrôlé, échec" "$([ "$CODE" -eq 1 ]; echo $?)"
rm "$REPO/docs/guide.md"
cp "$ICI/fixtures/mauvais/chemins.sh" "$REPO/README.md"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "fichier publiable à la racine (README.md) : contrôlé, échec" "$([ "$CODE" -eq 1 ]; echo $?)"

echo "== agents de projet (agents/<projet>/) : ignorés sans argument, contrôlés si on les passe en argument"
mkdir -p "$REPO/agents/un-projet"
echo 'agent général propre' > "$REPO/agents/general.md"
cp "$ICI/fixtures/mauvais/projets.md" "$REPO/agents/un-projet/agent-de-projet.md"
cp "$ICI/fixtures/mauvais/identite.md" "$REPO/agents/un-projet/identite.md"
rm -f "$REPO/README.md"
SORTIE="$(bash "$REPO/tests/controle-donnees-perso.sh" 2>&1)"; CODE=$?
verifier "sous-dossier agents/un-projet/ plein de noms de projets et d'adresses : ignoré (code 0)" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "…et ses fichiers ne sont pas comptés (3 fichiers : scripts/a.sh, le contrôle, agents/general.md)" "$(grep -q '^OK : 3 fichier' <<<"$SORTIE"; echo $?)"
cp "$ICI/fixtures/mauvais/projets.md" "$REPO/agents/general-mauvais.md"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "même contenu dans un agent GÉNÉRAL (agents/*.md) : contrôlé, échec" "$([ "$CODE" -eq 1 ]; echo $?)"
rm "$REPO/agents/general-mauvais.md"
bash "$REPO/tests/controle-donnees-perso.sh" "$REPO/agents/un-projet" >/dev/null 2>&1; CODE=$?
verifier "agents/un-projet passé en argument : contrôlé, échec" "$([ "$CODE" -eq 1 ]; echo $?)"
mkdir -p "$REPO/agents/un-projet/profond/encore"
cp "$ICI/fixtures/mauvais/projets.md" "$REPO/agents/un-projet/profond/encore/x.md"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "sous-dossier plus profond de agents/<projet>/ : ignoré aussi (code 0)" "$([ "$CODE" -eq 0 ]; echo $?)"
rm -rf "$REPO/agents/un-projet"
bash "$REPO/tests/controle-donnees-perso.sh" >/dev/null 2>&1; CODE=$?
verifier "dépôt sans agent de projet : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"

echo "== valeurs lues à l'exécution (catégorie COMPTE exigée, pas seulement un code 1)"
mkdir -p "$TMP/compte" "$TMP/dossier-perso" "$TMP/vide" "$TMP/binaire" "$TMP/illisible" "$TMP/nomvide"
NOM="$(id -un)"
printf 'cd /%s/projets\n' "$NOM" > "$TMP/compte/a.sh"
SORTIE="$(bash "$CTRL" "$TMP/compte" 2>&1)"; CODE=$?
verifier "le nom du compte courant dans un chemin est trouvé [COMPTE]" "$([ "$CODE" -eq 1 ] && grep -q '\[COMPTE\]' <<<"$SORTIE"; echo $?)"
printf 'LAB=%s/quelquepart\n' "$HOME" > "$TMP/dossier-perso/a.sh"
SORTIE="$(bash "$CTRL" "$TMP/dossier-perso" 2>&1)"; CODE=$?
verifier "la valeur de HOME est trouvée [COMPTE]" "$([ "$CODE" -eq 1 ] && grep -q '\[COMPTE\]' <<<"$SORTIE"; echo $?)"
printf 'Le lab de %s est un nom de projet.\n' "$NOM" > "$TMP/vide/a.md"
bash "$CTRL" "$TMP/vide" >/dev/null 2>&1; CODE=$?
verifier "le nom du compte seul, hors chemin ou adresse, n'est pas signalé" "$([ "$CODE" -eq 0 ]; echo $?)"
: > "$TMP/vide/a.md"
bash "$CTRL" "$TMP/vide" >/dev/null 2>&1; CODE=$?
verifier "un fichier vide passe" "$([ "$CODE" -eq 0 ]; echo $?)"

echo "== pas de « OK » silencieux"
printf 'texte\0binaire\n' > "$TMP/binaire/b.dat"
SORTIE="$(bash "$CTRL" "$TMP/binaire" 2>&1)"; CODE=$?
verifier "fichier binaire : échec [BINAIRE]" "$([ "$CODE" -eq 1 ] && grep -q '\[BINAIRE\]' <<<"$SORTIE"; echo $?)"
if [ "$(id -u)" -ne 0 ]; then
  echo "contenu" > "$TMP/illisible/x.txt"; chmod 000 "$TMP/illisible/x.txt"
  SORTIE="$(bash "$CTRL" "$TMP/illisible" 2>&1)"; CODE=$?
  verifier "fichier illisible (erreur de grep) : échec, pas de OK" "$([ "$CODE" -eq 1 ] && ! grep -q '^OK' <<<"$SORTIE"; echo $?)"
else
  echo "  SKIP fichier illisible (exécuté en root)"
fi
bash "$CTRL" "$TMP/nomvide" >/dev/null 2>&1; CODE=$?
verifier "dossier sans aucun fichier : échec" "$([ "$CODE" -eq 1 ]; echo $?)"

echo "== usage"
bash "$CTRL" "$TMP/inexistant" >/dev/null 2>&1; CODE=$?
verifier "dossier inexistant : code 2" "$([ "$CODE" -eq 2 ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
