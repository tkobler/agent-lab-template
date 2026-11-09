#!/usr/bin/env bash
# Cohérence skills <-> garde-fous : aucune skill de claude/skills/ n'écrit hors des chemins autorisés par claude/settings.json.
#   - chaque chemin « memory/… », « config/TASKS.md », « config/NOW.md » cité entre apostrophes inverses par une skill
#     doit être couvert par une entrée Edit(…) de la liste allow ;
#   - chaque « touch X » cité par une skill doit exister tel quel en Bash(touch X) dans allow ;
#   - la liste allow ne contient plus aucune trace des anciens chemins (dossier de données, repère de revue) ;
#   - le contrôle se vérifie lui-même sur un settings.json volontairement périmé (il doit alors échouer).
# Écritures connues hors liste allow (validées à la main par l'utilisateur, hors du champ de cette décision) :
#   config/projects/ (add-project, morning-review) et agents/ (create-agent) : non contrôlées ici.
# Usage : test-skills-permissions.sh        Code de sortie : 0 = tout passe.
set -uo pipefail
ICI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQ="$(dirname "$ICI")"
OK=0; KO=0
verifier() { if [ "$2" = 0 ]; then OK=$((OK + 1)); echo "  ok   $1"; else KO=$((KO + 1)); echo "  ECHEC $1"; fi; }

# controle <settings.json> : imprime chaque écriture de skill non couverte ; code 1 s'il y en a.
controle() {
  python3 -I -c '
import json, re, sys, glob
settings, skills = sys.argv[1], sys.argv[2]
allow = json.load(open(settings))["permissions"]["allow"]
def rx(g):
    return re.compile("^" + re.escape(g).replace(r"\*\*", ".*").replace(r"\*", "[^/]*") + "$")
edits = []
for a in allow:
    m = re.fullmatch(r"Edit\((.*)\)", a)
    if m:
        p = m.group(1)
        if p.startswith("@"):
            p = p.split("/", 1)[1]          # retire le marqueur de chemin du lab
        edits.append(rx(p))
touches = {a[len("Bash("):-1] for a in allow if a.startswith("Bash(touch ")}
bad = []
for f in sorted(glob.glob(skills + "/*/SKILL.md")):
    nom = f.split("/")[-2]
    txt = open(f, encoding="utf-8").read()
    for chemin in sorted(set(re.findall(r"`((?:memory/|config/TASKS\.md|config/NOW\.md)[^`\s]*)`", txt))):
        c = chemin.rstrip(".,;:")
        if not any(e.match(c) for e in edits):
            bad.append("%s : chemin non autorisé en écriture : %s" % (nom, c))
    for cmd in sorted(set(re.findall(r"`(touch [^`]+)`", txt))):
        if cmd not in touches:
            bad.append("%s : commande non autorisée : %s" % (nom, cmd))
print("\n".join(bad))
sys.exit(1 if bad else 0)
' "$1" "$SQ/claude/skills"
}

echo "== claude/settings.json couvre les écritures des skills"
SORTIE="$(controle "$SQ/claude/settings.json")"; CODE=$?
[ -n "$SORTIE" ] && echo "$SORTIE" | sed 's/^/       /'
verifier "toutes les écritures de skills (memory/**, TASKS, NOW, touch) sont autorisées" "$([ "$CODE" -eq 0 ]; echo $?)"
verifier "allow : Edit(@LAB_PERM@/memory/**) présent" "$(grep -qF '"Edit(@LAB_PERM@/memory/**)"' "$SQ/claude/settings.json"; echo $?)"
verifier "allow : Bash(touch .review-done) présent" "$(grep -qF '"Bash(touch .review-done)"' "$SQ/claude/settings.json"; echo $?)"
ANC="memo""ire"; ANR="revue""-faite"
verifier "aucune trace des anciens chemins dans settings.json" "$(! grep -qE "$ANC|$ANR" "$SQ/claude/settings.json"; echo $?)"

echo "== le contrôle détecte un settings.json périmé"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/test-skills-perm.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
sed -e "s#/memory/\*\*#/$ANC/**#" -e "s#touch \.review-done#touch $ANC/.$ANR#" "$SQ/claude/settings.json" > "$TMP/vieux.json"
SORTIE="$(controle "$TMP/vieux.json")"; CODE=$?
verifier "settings périmé : le contrôle échoue" "$([ "$CODE" -eq 1 ]; echo $?)"
verifier "…et nomme le chemin memory/ et la commande touch" \
  "$(grep -q 'chemin non autorisé en écriture : memory/' <<<"$SORTIE" && grep -q 'commande non autorisée : touch .review-done' <<<"$SORTIE"; echo $?)"
printf '%s\n' '{"permissions":{"allow":["Edit(@LAB_PERM@/config/TASKS.md)","Edit(@LAB_PERM@/config/NOW.md)","Edit(@LAB_PERM@/memory/**)","Bash(touch .review-done)"]}}' > "$TMP/ok.json"
verifier "settings minimal correct : le contrôle passe" "$(controle "$TMP/ok.json" >/dev/null; echo $?)"

echo "Résultat : $OK réussi(s), $KO échec(s)"
[ "$KO" -eq 0 ]
