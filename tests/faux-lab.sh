#!/usr/bin/env bash
# Installe un FAUX LAB dans un dossier temporaire (install.sh + config.example.env) avec un faux projet git,
# puis lance « night.sh <N> --check » et vérifie les codes de sortie et les messages.
# Sécurité : HOME est remplacé par un dossier vide pour tout ce qui est lancé ; aucun claude n'est lancé
# (--check ne lance rien), le vrai lab et ~/Library/LaunchAgents ne sont pas touchés.
# Usage : faux-lab.sh        Code de sortie : 0 = tous les contrôles passent. Nécessite macOS (date -v, stat -f).
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
source "$ICI/anciens-noms.sh"      # anciens noms français, assemblés (pour vérifier qu'ils ne sont plus ni créés ni lus)
if [ "$(uname)" != Darwin ]; then echo "SKIP : ce test suppose macOS (date -v dans night.sh)."; exit 0; fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/faux-lab.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"      # chemin normalisé (TMPDIR se termine souvent par /), comme celui que verra install.sh
trap 'rm -rf "$TMP"' EXIT
ANC_MEM="memo""ire"; ANC_SUI="su""ivi"; ANC_REV="revue-""faite"; ANC_ETAT="et""at.md"; ANC_DEC="a-de""cider"; ANC_REVUE="revue-""matin"
FAUXHOME="$TMP/home"; mkdir -p "$FAUXHOME"
RACINE="$TMP/racine"; LAB="$RACINE/lab"
OK=0; KO=0; SKIP=0
verifier() {  # <nom> <0 = vrai>
  if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi
}
# Tout ce qui tourne ici voit HOME=$FAUXHOME
dans_faux_home() { HOME="$FAUXHOME" "$@"; }
nuit() { HOME="$FAUXHOME" "$@" 2>&1; }

echo "== installation du faux lab dans un dossier temporaire"
SORTIE="$(dans_faux_home bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin --prefix com.exemple 2>&1)"; CODE=$?
echo "$SORTIE" | sed 's/^/    | /'
verifier "install.sh : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "aucun avertissement ATTENTION ni SKIP à l'installation" "$(! grep -qE 'ATTENTION|SKIP' <<<"$SORTIE"; echo $?)"
verifier "config.env créé avec le lab de cette installation" "$(grep -q "^LAB=\"$LAB\"" "$LAB/config.env"; echo $?)"
verifier "config.env : aucun marqueur restant" "$(! grep -q '@[A-Z_]*@' "$LAB/config.env"; echo $?)"
verifier "config.env : préfixe LaunchAgent réglé" "$(grep -q '^PREFIXE_LAUNCHAGENT="com.exemple"' "$LAB/config.env"; echo $?)"
verifier "night.sh est exécutable après installation" "$([ -x "$LAB/scripts/night.sh" ]; echo $?)"
verifier "config/TASKS.md et config/NOW.md créés à partir des gabarits" "$([ -f "$LAB/config/TASKS.md" ] && [ -f "$LAB/config/NOW.md" ]; echo $?)"
# Mémoire (D2 du 21/10) : memory/ et .review-done, plus les anciens dossiers
verifier "memory/ créé, avec memory/Home.md" "$([ -d "$LAB/memory" ] && [ -f "$LAB/memory/Home.md" ]; echo $?)"
verifier "notes du projet lab : lab-Project, lab-Log, lab-Decisions, lab-Agent-Knowledge, lab-Running, lab-Team" \
  "$(for n in Project Log Decisions Agent-Knowledge Running Team; do [ -f "$LAB/memory/lab/lab-$n.md" ] || exit 1; done; echo $?)"
verifier "reports/ créé à l'installation (dossier vide, lu par la skill morning-review)" "$([ -d "$LAB/reports" ] && [ -z "$(ls -A "$LAB/reports")" ]; echo $?)"
verifier "lab-Team : titre lab, liens [[Home]] et lab-Project, sections agents et skills" \
  "$(T="$LAB/memory/lab/lab-Team.md"; head -1 "$T" | grep -q 'lab' && grep -qF '[[Home]]' "$T" && grep -qF '[[lab/lab-Project]]' "$T" && grep -q '^## Agents de base' "$T" && grep -q '^## Skills' "$T"; echo $?)"
verifier "toute page lab-*.md liée par CLAUDE.md existe (lab-Agent-Knowledge, lab-Decisions, lab-Running, lab-Team)" \
  "$(for n in $(grep -o 'memory/lab/lab-[A-Za-z-]*\.md' "$LAB/CLAUDE.md" | sort -u); do [ -f "$LAB/$n" ] || exit 1; done; echo $?)"
verifier "notes du lab : nom du projet « lab » dans le titre, aucun <projet> restant" \
  "$(head -1 "$LAB/memory/lab/lab-Project.md" | grep -q 'lab' && ! grep -rqF '<projet>' "$LAB/memory"; echo $?)"
verifier ".review-done créé (repère de revue, fichier vide)" "$([ -f "$LAB/.review-done" ] && [ ! -s "$LAB/.review-done" ]; echo $?)"
verifier "ni $ANC_MEM/ ni $ANC_SUI/ créés" "$([ ! -e "$LAB/$ANC_MEM" ] && [ ! -e "$LAB/$ANC_SUI" ]; echo $?)"
verifier "anciens gabarits state/to-decide/decisions absents de templates/, nouveaux gabarits présents" \
  "$([ ! -e "$LAB/templates/state.empty.md" ] && [ ! -e "$LAB/templates/to-decide.empty.md" ] && [ ! -e "$LAB/templates/decisions.empty.md" ] && [ -f "$LAB/templates/note-Project.empty.md" ] && [ -f "$LAB/templates/note-Log.empty.md" ] && [ -f "$LAB/templates/note-Decisions.empty.md" ] && [ -f "$LAB/templates/note-Agent-Knowledge.empty.md" ]; echo $?)"
verifier "morning-retry.sh lit .review-done, pas l'ancien repère $ANC_MEM/.$ANC_REV" \
  "$(grep -q 'review-done' "$LAB/scripts/morning-retry.sh" && ! grep -qE "$ANC_MEM|$ANC_REV" "$LAB/scripts/morning-retry.sh"; echo $?)"
verifier "manager.sh : prompt du matin sur memory/lab/lab-Agent-Knowledge.md et morning-review, aucun ancien nom" \
  "$(grep -qF 'memory/lab/lab-Agent-Knowledge.md' "$LAB/scripts/manager.sh" && grep -q 'morning-review' "$LAB/scripts/manager.sh" && ! grep -qE "$ANC_MEM|$ANC_ETAT|$ANC_DEC|$ANC_REVUE" "$LAB/scripts/manager.sh"; echo $?)"
verifier "dossiers de données anglais : config/projects, reports, data/logs, data/projects, data/worktrees" "$([ -d "$LAB/config/projects" ] && [ -d "$LAB/reports" ] && [ -d "$LAB/data/logs" ] && [ -d "$LAB/data/projects" ] && [ -d "$LAB/data/worktrees" ] && [ ! -e "$LAB/logs" ]; echo $?)"
verifier "aucun ancien dossier ni fichier de données ($AN_FICHES, $AN_RAPPORTS, $AN_MODELES, ${AN_TASKS_UP}.md, ${AN_NOW_UP}.md)" \
  "$([ ! -e "$LAB/$AN_FICHES" ] && [ ! -e "$LAB/$AN_RAPPORTS" ] && [ ! -e "$LAB/$AN_MODELES" ] && [ ! -e "$LAB/${AN_TASKS_UP}.md" ] && [ ! -e "$LAB/${AN_NOW_UP}.md" ]; echo $?)"
verifier "gabarits en anglais copiés dans templates/ (TASKS.empty.md, NOW.empty.md, *.plist.template)" \
  "$([ -f "$LAB/templates/TASKS.empty.md" ] && [ -f "$LAB/templates/NOW.empty.md" ] && [ -f "$LAB/templates/night.plist.template" ]; echo $?)"
verifier "config/TASKS.md installé = gabarit TASKS.empty.md ; config/NOW.md = NOW.empty.md" \
  "$(cmp -s "$LAB/config/TASKS.md" "$LAB/templates/TASKS.empty.md" && cmp -s "$LAB/config/NOW.md" "$LAB/templates/NOW.empty.md"; echo $?)"
verifier "agents de base installés" "$([ -f "$LAB/agents/codeur.md" ] && [ -f "$LAB/agents/chercheur.md" ] && [ -f "$LAB/agents/relecteur.md" ] && [ -f "$LAB/agents/testeur.md" ]; echo $?)"
verifier "aucun agent ni outil propre à un projet à la racine de agents/ ni dans scripts/ (les agents de projet sont dans agents/<projet>/)" \
  "$([ "$(ls "$LAB"/agents/*.md | xargs -n1 basename | tr '\n' ' ')" = 'chercheur.md codeur.md relecteur.md testeur.md ' ] && ! ls "$LAB"/scripts | grep -qiE 'simul'; echo $?)"
PLIST="$LAB/launchagents/com.exemple.morning-retry.plist"
verifier "modèle de LaunchAgent rendu avec le préfixe et le chemin du faux lab" \
  "$(grep -q "<string>com.exemple.morning-retry</string>" "$PLIST" && grep -q "<string>$LAB/scripts/morning-retry.sh</string>" "$PLIST"; echo $?)"
if command -v plutil >/dev/null 2>&1; then verifier "plist valide (plutil -lint)" "$(plutil -lint "$PLIST" >/dev/null 2>&1; echo $?)"; fi
verifier "settings.json installé : chemins du faux lab, aucun marqueur" \
  "$(grep -q "$(printf '%s' "$LAB" | sed 's/[^A-Za-z0-9]/./g')" "$LAB/.claude/settings.json" && ! grep -q '@[A-Z_]*@' "$LAB/.claude/settings.json"; echo $?)"

echo "== faux projet git et faux config/TASKS.md"
PROJ="$RACINE/projets/demo"
mkdir -p "$PROJ"
git -C "$PROJ" init -q -b main
git -C "$PROJ" -c user.name=Essai -c user.email=essai@exemple.com commit -q --allow-empty -m "init"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\nMODELE="haiku"\n' "$PROJ" > "$LAB/config/projects/demo.env"
cat > "$LAB/config/TASKS.md" <<'EOF'
# Tâches de la prochaine nuit

<!-- commentaire ignoré
## ROUND 1
projet: fantome
branche: claude/fantome
- [codeur] ne doit pas être lu
-->

## ROUND 1
projet: demo
branche: claude/essai

- [codeur] Première tâche
  Critère de fin : tests verts.
- [chercheur] Seconde tâche

## ROUND 2
projet:
branche:

## ROUND 3
projet: demo
branche: master

- [codeur] Mauvaise branche

## ROUND 4
projet: inconnu
branche: claude/x

- [codeur] Projet absent

## ROUND 6
projet: demo
branche: claude/agents

- [agent-demo] Agent du projet (agents/demo/)
- [agent-autre] Agent d'un autre projet (agents/autre/) : introuvable pour demo
- [codeur] Doublon : le général gagne sur agents/demo/codeur.md
- [fantome-total] Tag qui n'existe nulle part
EOF
# Agents de projet : agents/<projet>/<tag>.md (agent du projet), agents/autre/ (autre projet), doublon avec un général
mkdir -p "$LAB/agents/demo" "$LAB/agents/autre"
printf -- '---\nname: agent-demo\nmodel: opus\n---\nCorps.\n' > "$LAB/agents/demo/agent-demo.md"
printf -- '---\nname: agent-autre\nmodel: opus\n---\nCorps.\n' > "$LAB/agents/autre/agent-autre.md"
printf -- '---\nname: codeur\nmodel: opus\n---\nCorps.\n' > "$LAB/agents/demo/codeur.md"

echo "== night.sh 1 --check (cas nominal, exécution directe puis sous le bash du système)"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
echo "$SORTIE" | sed 's/^/    | /'
verifier "code de sortie 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "message OK avec 2 tâches, projet demo, branche claude/essai" "$(grep -q 'OK — round 1 : 2 tâche(s) sur « demo », branche claude/essai' <<<"$SORTIE"; echo $?)"
verifier "le commentaire HTML n'est pas lu (pas de projet fantome)" "$(! grep -q fantome <<<"$SORTIE"; echo $?)"
verifier "modèle du projet retenu (niveau projet)" "$(grep -q 'Modèle des rounds : haiku (niveau projet)' <<<"$SORTIE"; echo $?)"
verifier "agent de base en inherit : suit le projet" "$(grep -q '\[codeur\] modèle : haiku (niveau projet)' <<<"$SORTIE"; echo $?)"
SORTIE="$(nuit /bin/bash "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
verifier "même résultat sous /bin/bash (code 0)" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 1' <<<"$SORTIE"; echo $?)"

echo "== agents de projet (agents/<projet>/<tag>.md) : trouvés par tag, le général gagne, tag absent signalé"
SORTIE="$(nuit "$LAB/scripts/night.sh" 6 --check)"; CODE=$?
echo "$SORTIE" | sed 's/^/    | /'
verifier "round 6 : code 0 (un tag introuvable n'empêche pas --check)" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 6 : 4 tâche(s)' <<<"$SORTIE"; echo $?)"
verifier "agent du projet trouvé, son modèle (niveau agent) affiché" "$(grep -q '\[agent-demo\] modèle : opus (niveau agent)' <<<"$SORTIE"; echo $?)"
verifier "agent d'un autre projet : introuvable, aucun modèle affiché" \
  "$(grep -q '\[agent-autre\] pas d.agents/agent-autre.md ni d.agents/demo/agent-autre.md' <<<"$SORTIE" && ! grep -q '\[agent-autre\] modèle' <<<"$SORTIE"; echo $?)"
verifier "doublon : l'agent général (inherit, donc le projet haiku) gagne sur agents/demo/codeur.md (opus)" \
  "$(grep -q '\[codeur\] modèle : haiku (niveau projet)' <<<"$SORTIE" && ! grep -q '\[codeur\] modèle : opus' <<<"$SORTIE"; echo $?)"
verifier "doublon : avertissement" "$(grep -q 'ATTENTION : agents/codeur.md (général) et agents/demo/codeur.md (projet)' <<<"$SORTIE"; echo $?)"
verifier "tag introuvable partout : signalé" "$(grep -q '\[fantome-total\] pas d.agents/fantome-total.md' <<<"$SORTIE"; echo $?)"
# Extrait réel : les agents d'un vrai projet, rangés dans agents/<projet>/ (absents du lab publiable : SKIP)
# Découverte générique (aucun nom en dur) : premier agents/<projet>/<agent>.md, hors le projet factice « demo » du test
PR_REEL=""; AG_REEL=""
for d in "$LAB"/agents/*/; do
  [ -d "$d" ] || continue
  [ "$(basename "$d")" = demo ] && continue
  for f in "$d"*.md; do
    [ -f "$f" ] || continue
    PR_REEL="$(basename "$d")"; AG_REEL="$(basename "$f" .md)"; break 2
  done
done
if [ -n "$PR_REEL" ] && [ -f "$LAB/agents/$PR_REEL/$AG_REEL.md" ]; then
  printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$PROJ" > "$LAB/config/projects/$PR_REEL.env"
  printf '## ROUND 7\nprojet: %s\nbranche: claude/essai\n\n- [%s] Tâche réelle\n- [codeur] Tâche générale\n' "$PR_REEL" "$AG_REEL" >> "$LAB/config/TASKS.md"
  SORTIE="$(nuit "$LAB/scripts/night.sh" 7 --check)"; CODE=$?
  echo "$SORTIE" | sed 's/^/    | /'
  verifier "agent réel d'un projet : code 0 et « [$AG_REEL] modèle : … (niveau agent) » affiché" \
    "$([ "$CODE" -eq 0 ] && grep -qE "\[$AG_REEL\] modèle : [^ ]+ \(niveau agent\)" <<<"$SORTIE"; echo $?)"
  verifier "…et l'agent général reste trouvé" "$(grep -q '\[codeur\] modèle :' <<<"$SORTIE"; echo $?)"
  printf '## ROUND 8\nprojet: demo\nbranche: claude/essai\n\n- [%s] Agent d un autre projet\n' "$AG_REEL" >> "$LAB/config/TASKS.md"
  SORTIE="$(nuit "$LAB/scripts/night.sh" 8 --check)"; CODE=$?
  verifier "agent réel demandé depuis un autre projet : introuvable" "$(grep -q "\[$AG_REEL\] pas d.agents/" <<<"$SORTIE" && ! grep -q "\[$AG_REEL\] modèle" <<<"$SORTIE"; echo $?)"
  rm -f "$LAB/config/projects/$PR_REEL.env"
else
  SKIP=$((SKIP + 1)); echo "  SKIP agents de projet réels absents de ce lab (lab publiable)"
fi

echo "== cas d'erreur et cas vides"
SORTIE="$(nuit "$LAB/scripts/night.sh" 2 --check)"; CODE=$?
verifier "round 2 sans tâche : code 0 et « aucune tâche »" "$([ "$CODE" -eq 0 ] && grep -q 'aucune tâche' <<<"$SORTIE"; echo $?)"
SORTIE="$(nuit "$LAB/scripts/night.sh" 3 --check)"; CODE=$?
verifier "branche hors claude/ : code 1 et refus" "$([ "$CODE" -eq 1 ] && grep -q 'doit commencer par claude/' <<<"$SORTIE"; echo $?)"
SORTIE="$(nuit "$LAB/scripts/night.sh" 4 --check)"; CODE=$?
verifier "projet inconnu : code 1" "$([ "$CODE" -eq 1 ] && grep -q 'Projet inconnu' <<<"$SORTIE"; echo $?)"
SORTIE="$(nuit "$LAB/scripts/night.sh" 5 --check)"; CODE=$?
verifier "round absent de config/TASKS.md : code 0 et « aucune tâche »" "$([ "$CODE" -eq 0 ] && grep -q 'aucune tâche' <<<"$SORTIE"; echo $?)"
SORTIE="$(nuit "$LAB/scripts/night.sh" abc --check)"; CODE=$?
verifier "round inconnu : code 2" "$([ "$CODE" -eq 2 ]; echo $?)"
# Anciens noms français : refusés net (sinon l'ancienne option ignorée lancerait un vrai round).
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 "$AN_VERIFIER")"; CODE=$?
verifier "ancienne option $AN_VERIFIER refusée : code 2, rien lancé" "$([ "$CODE" -eq 2 ] && ! grep -q 'OK — round' <<<"$SORTIE" && [ -z "$(ls -A "$LAB/data/logs")" ]; echo $?)"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --n-importe-quoi)"; CODE=$?
verifier "option inconnue refusée : code 2" "$([ "$CODE" -eq 2 ]; echo $?)"
SORTIE="$(nuit "$LAB/scripts/night.sh" "$AN_NOW" --check)"; CODE=$?
verifier "ancien nom de round « $AN_NOW » refusé : code 2" "$([ "$CODE" -eq 2 ]; echo $?)"

echo "== round « now » (config/NOW.md, section « ## NOW »)"
SORTIE="$(nuit "$LAB/scripts/night.sh" now --check)"; CODE=$?
verifier "now --check avec le gabarit vide : code 0 et « aucune tâche »" "$([ "$CODE" -eq 0 ] && grep -q 'aucune tâche' <<<"$SORTIE"; echo $?)"
printf '# Round\n\n## NOW\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Tâche immédiate\n' > "$LAB/config/NOW.md"
SORTIE="$(nuit "$LAB/scripts/night.sh" now --check)"; CODE=$?
verifier "now --check avec une tâche : code 0, projet demo, branche claude/essai" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round now : 1 tâche(s) sur « demo », branche claude/essai' <<<"$SORTIE"; echo $?)"
printf '# Round\n\n## %s\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Ancien titre\n' "$AN_NOW_UP" > "$LAB/config/NOW.md"
SORTIE="$(nuit "$LAB/scripts/night.sh" now --check)"; CODE=$?
verifier "ancienne section « ## $AN_NOW_UP » ignorée : aucune tâche" "$([ "$CODE" -eq 0 ] && grep -q 'aucune tâche' <<<"$SORTIE"; echo $?)"
cp "$LAB/templates/NOW.empty.md" "$LAB/config/NOW.md"
printf '# Anciens emplacements\n\n## ROUND 1\nprojet: demo\nbranche: claude/essai\n\n- [codeur] Dans l ancien fichier\n' > "$LAB/${AN_TASKS_UP}.md"
SORTIE="$(nuit "$LAB/scripts/night.sh" 2 --check)"; CODE=$?
verifier "l'ancien fichier de tâches à la racine n'est plus lu (round 2 : aucune tâche)" "$([ "$CODE" -eq 0 ] && grep -q 'aucune tâche' <<<"$SORTIE"; echo $?)"
rm -f "$LAB/${AN_TASKS_UP}.md"

echo "== garde-fous dérivés de LAB"
verifier "--check n'a rien écrit dans reports/ ni logs/" "$([ -z "$(ls -A "$LAB/reports")$(ls -A "$LAB/data/logs")" ]; echo $?)"
verifier "HOME de substitution intact (rien créé : ni Library, ni LaunchAgents)" "$([ -z "$(ls -A "$FAUXHOME")" ]; echo $?)"
# Retire un chemin de la PREMIÈRE liste d'interdits (construire_permissions) : la liste « critiques » de
# verifier_permissions doit le voir et refuser le round. C'est le test « un renommage oublié retire un garde-fou ».
LN="$(grep -n "for p in 'scripts/\*\*'" "$LAB/scripts/night.sh" | head -n 1 | cut -d: -f1)"
ANC_M="memo""ire"; ANC_S="su""ivi"
verifier "night.sh protège memory/** dans les 2 listes, plus les anciens dossiers ($ANC_M/**, $ANC_S/**)" \
  "$([ "$(grep -c "'memory/\*\*'" "$LAB/scripts/night.sh")" -eq 2 ] && ! grep -qE "'($ANC_M|$ANC_S)/\*\*'" "$LAB/scripts/night.sh"; echo $?)"
sed "${LN}s# 'memory/\*\*'##" "$LAB/scripts/night.sh" > "$TMP/night-mutated.sh"
verifier "la mutation a bien retiré memory/** de la première liste seulement" \
  "$([ "$(grep -c "'memory/\*\*'" "$TMP/night-mutated.sh")" -eq 1 ]; echo $?)"
cp "$TMP/night-mutated.sh" "$LAB/scripts/night-mutated.sh"
SORTIE="$(nuit bash "$LAB/scripts/night-mutated.sh" 1 --check)"; CODE=$?
verifier "garde-fou retiré par erreur : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
verifier "…avec le message « interdit critique absent » sur memory/**" "$(grep -q 'interdit critique absent : « Edit(.*/memory/\*\*) »' <<<"$SORTIE"; echo $?)"
rm -f "$LAB/scripts/night-mutated.sh"
# Même mutation pour chacun des chemins de données renommés : le retrait de l'un d'eux doit être refusé.
for chemin in 'config/projects/**' 'config/TASKS.md' 'config/NOW.md'; do
  motif="${chemin//\*/\\*}"
  sed "${LN}s# '${motif}'##" "$LAB/scripts/night.sh" > "$LAB/scripts/night-mutated.sh"
  verifier "mutation : « $chemin » retiré de la première liste seulement" \
    "$([ "$(grep -c "'$motif'" "$LAB/scripts/night-mutated.sh")" -eq 1 ]; echo $?)"
  SORTIE="$(nuit bash "$LAB/scripts/night-mutated.sh" 1 --check)"; CODE=$?
  verifier "garde-fou « $chemin » retiré par erreur : code 1 et « interdit critique absent »" \
    "$([ "$CODE" -eq 1 ] && grep -qF "interdit critique absent : « Edit(" <<<"$SORTIE" && grep -qF "$chemin" <<<"$SORTIE"; echo $?)"
  rm -f "$LAB/scripts/night-mutated.sh"
done
# Un interdit supplémentaire de fiche ne doit pas gêner, une autorisation trop large doit être refusée
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\nOUTILS_EXTRA="Bash(bash *)"\n' "$PROJ" > "$LAB/config/projects/demo.env"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
verifier "OUTILS_EXTRA trop large dans une fiche : code 1" "$([ "$CODE" -eq 1 ] && grep -q 'PERMISSIONS : autorisation trop large' <<<"$SORTIE"; echo $?)"

echo "== LAB de config.env différent du lab installé (garde de cohérence de night.sh)"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$PROJ" > "$LAB/config/projects/demo.env"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
verifier "VERT : config.env cohérent, round accepté (code 0)" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 1' <<<"$SORTIE"; echo $?)"
cp "$LAB/config.env" "$TMP/config.env.sauvegarde"
mkdir -p "$TMP/ailleurs"
sed "s#^LAB=.*#LAB=\"$TMP/ailleurs\"#" "$TMP/config.env.sauvegarde" > "$LAB/config.env"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
verifier "ROUGE : LAB pointant ailleurs, même en --check : code 1" "$([ "$CODE" -eq 1 ] && grep -q "n'est pas le dossier de ce lab" <<<"$SORTIE" && ! grep -q 'OK — round' <<<"$SORTIE"; echo $?)"
ln -s "$LAB" "$TMP/lien-lab"
sed "s#^LAB=.*#LAB=\"$TMP/lien-lab\"#" "$TMP/config.env.sauvegarde" > "$LAB/config.env"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
verifier "ROUGE : LAB donné par un lien symbolique : code 1" "$([ "$CODE" -eq 1 ] && grep -q 'lien symbolique' <<<"$SORTIE"; echo $?)"
sed "s#^LAB=.*#LAB=\"$TMP/inexistant\"#" "$TMP/config.env.sauvegarde" > "$LAB/config.env"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
verifier "ROUGE : LAB inexistant : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
verifier "aucun rapport d'échec écrit dans le mauvais dossier" "$([ -z "$(ls -A "$TMP/ailleurs")" ] && [ -z "$(ls -A "$LAB/reports")" ]; echo $?)"
cp "$TMP/config.env.sauvegarde" "$LAB/config.env"
SORTIE="$(nuit "$LAB/scripts/night.sh" 1 --check)"; CODE=$?
verifier "VERT : config.env restauré, round accepté" "$([ "$CODE" -eq 0 ]; echo $?)"

echo "== LAB installé SOUS le dossier personnel (forme ~/… des permissions, garde de cohérence)"
HOME2="$TMP/home2"; LAB2="$HOME2/racine/lab"; mkdir -p "$HOME2"
HOME="$HOME2" bash "$ICI/install-en-place.sh" "$LAB2" --brew-bin /usr/bin >/dev/null 2>&1; CODE=$?
verifier "installation d'un lab sous HOME : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
# Installation SANS --prefix : le préfixe par défaut est com.agent-lab (l'ancien préfixe n'existe plus nulle part)
verifier "préfixe par défaut : config.env PREFIXE_LAUNCHAGENT=\"com.agent-lab\"" "$(grep -q '^PREFIXE_LAUNCHAGENT="com.agent-lab"' "$LAB2/config.env"; echo $?)"
verifier "préfixe par défaut : launchagents/com.agent-lab.night.plist, étiquette com.agent-lab.night" \
  "$([ -f "$LAB2/launchagents/com.agent-lab.night.plist" ] && grep -q '<string>com.agent-lab.night</string>' "$LAB2/launchagents/com.agent-lab.night.plist"; echo $?)"
verifier "préfixe par défaut : 5 plist com.agent-lab.*, aucun autre préfixe" \
  "$([ "$(ls "$LAB2/launchagents" | grep -c '^com\.agent-lab\.')" -eq 5 ] && [ "$(ls "$LAB2/launchagents" | wc -l | tr -d ' ')" -eq 5 ]; echo $?)"
verifier "l'ancien préfixe n'apparaît nulle part dans le lab installé" "$(! grep -rq --exclude-dir=.git --exclude-dir=tests --exclude=README.md "$AN_PREFIXE" "$LAB2"; echo $?)"   # README et tests/ exclus
verifier "l'ancien nom du dépôt et son préfixe n'apparaissent nulle part dans le lab installé" "$(! grep -rqE --exclude-dir=.git "${AN_DEPOT}|${AN_PREFIXE_DEPOT}" "$LAB2"; echo $?)"
# Décision du 24/10 (l'ancien nom de l'installation n'existe plus) : ni le préfixe intermédiaire ni le dossier de mémoire de l'ancien nom (cas négatifs)
verifier "ni le préfixe $AN_PREFIXE_INTERM ni $AN_MEM_ANCIEN dans le lab installé (contenu et chemins)" \
  "$(! grep -rqE --exclude-dir=.git --exclude-dir=tests --exclude=README.md "${AN_PREFIXE_INTERM}|${AN_MEM_ANCIEN}" "$LAB2" && [ ! -e "$LAB2/memory/${AN_MEM_ANCIEN#memory/}" ] && [ -d "$LAB2/memory/lab" ]; echo $?)"
verifier "settings.json en forme ~/ (aucun chemin absolu du faux HOME)" \
  "$(grep -qF '"Edit(~/racine/lab/config/TASKS.md)"' "$LAB2/.claude/settings.json" && ! grep -qF "$HOME2" "$LAB2/.claude/settings.json"; echo $?)"
printf 'REPO_PATH="%s"\nBRANCHE_BASE="main"\n' "$PROJ" > "$LAB2/config/projects/demo.env"
cp "$LAB/config/TASKS.md" "$LAB2/config/TASKS.md"
nuit2() { HOME="$HOME2" "$@" 2>&1; }
SORTIE="$(nuit2 "$LAB2/scripts/night.sh" 1 --check)"; CODE=$?
verifier "VERT : LAB sous HOME, config.env cohérent : round accepté (code 0)" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 1' <<<"$SORTIE"; echo $?)"
cp "$LAB2/config.env" "$TMP/config2.sauvegarde"
sed "s#^LAB=.*#LAB=\"\$HOME/racine/lab\"#" "$TMP/config2.sauvegarde" > "$LAB2/config.env"
SORTIE="$(nuit2 "$LAB2/scripts/night.sh" 1 --check)"; CODE=$?
verifier "VERT : LAB écrit « \$HOME/racine/lab » dans config.env (même dossier) : accepté" "$([ "$CODE" -eq 0 ] && grep -q 'OK — round 1' <<<"$SORTIE"; echo $?)"
sed "s#^LAB=.*#LAB=\"~/racine/lab\"#" "$TMP/config2.sauvegarde" > "$LAB2/config.env"
SORTIE="$(nuit2 "$LAB2/scripts/night.sh" 1 --check)"; CODE=$?
verifier "ROUGE : LAB écrit « ~/racine/lab » (tilde non développé entre guillemets) : code 1" "$([ "$CODE" -eq 1 ] && grep -q "n'est pas le dossier de ce lab" <<<"$SORTIE"; echo $?)"
mkdir -p "$HOME2/autre-lab"
sed "s#^LAB=.*#LAB=\"$HOME2/autre-lab\"#" "$TMP/config2.sauvegarde" > "$LAB2/config.env"
SORTIE="$(nuit2 "$LAB2/scripts/night.sh" 1 --check)"; CODE=$?
verifier "ROUGE : LAB de config.env = autre dossier sous HOME : code 1, rien écrit là-bas" \
  "$([ "$CODE" -eq 1 ] && grep -q "n'est pas le dossier de ce lab" <<<"$SORTIE" && [ -z "$(ls -A "$HOME2/autre-lab")" ]; echo $?)"
sed "s#^LAB=.*#LAB=\"$HOME2/racine/lab/..\"#" "$TMP/config2.sauvegarde" > "$LAB2/config.env"
SORTIE="$(nuit2 "$LAB2/scripts/night.sh" 1 --check)"; CODE=$?
verifier "ROUGE : LAB = dossier parent (racine/lab/..) : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
cp "$TMP/config2.sauvegarde" "$LAB2/config.env"
verifier "HOME de substitution n° 2 : rien créé hors de racine/ et autre-lab/" "$([ "$(ls -A "$HOME2" | tr '\n' ' ')" = "autre-lab racine " ]; echo $?)"

echo "== installation répétée et valeurs refusées"
echo '# réglage local ajouté à la main' >> "$LAB/config.env"
echo 'note ajoutée à la main' >> "$LAB/memory/lab/lab-Log.md"
dans_faux_home bash "$ICI/install-en-place.sh" "$LAB" --brew-bin /usr/bin >/dev/null 2>&1; CODE=$?
verifier "réinstallation : code 0" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "réinstallation : config.env conservé (réglage local toujours là)" "$(grep -q 'réglage local ajouté' "$LAB/config.env"; echo $?)"
verifier "réinstallation : config/projects/demo.env conservé" "$([ -f "$LAB/config/projects/demo.env" ]; echo $?)"
verifier "réinstallation : notes de memory/ conservées (non réécrites par les gabarits)" "$(grep -q 'note ajoutée à la main' "$LAB/memory/lab/lab-Log.md"; echo $?)"
verifier "réinstallation : config/TASKS.md conservé (non réécrit par le gabarit)" "$(grep -q 'projet: demo' "$LAB/config/TASKS.md"; echo $?)"
dans_faux_home bash "$ICI/install-en-place.sh" "$TMP/autre" --prefix 'a"b' >/dev/null 2>&1; CODE=$?
verifier "préfixe avec guillemet refusé : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
for car in '&' '<' "'"; do
  dans_faux_home bash "$ICI/install-en-place.sh" "$TMP/autre" --prefix "a${car}b" >/dev/null 2>&1; CODE=$?
  verifier "préfixe avec « $car » refusé : code 1" "$([ "$CODE" -eq 1 ]; echo $?)"
done
dans_faux_home bash "$SQ/install.sh" --inconnue >/dev/null 2>&1; CODE=$?
verifier "option inconnue : code 2 (l'installation sans argument est testée dans test-install-defaut.sh)" "$([ "$CODE" -eq 2 ]; echo $?)"
dans_faux_home bash "$LAB/install.sh" "$TMP/cible-ailleurs" >/dev/null 2>&1; CODE=$?
verifier "dossier cible refusé (install.sh n'installe plus qu'en place) : code 2, rien créé" "$([ "$CODE" -eq 2 ] && [ ! -e "$TMP/cible-ailleurs" ]; echo $?)"
verifier "HOME de substitution toujours intact" "$([ -z "$(ls -A "$FAUXHOME")" ]; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s), $SKIP ignoré(s)"
[ "$KO" -eq 0 ]
