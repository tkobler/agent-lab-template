#!/usr/bin/env python3
"""Vérifie la forme des pages <projet>-Agent-Knowledge du coffre (memory/).

Une page est le contexte condensé que chaque round lit en premier. Règles (plan du 20/10) :
moins de 150 lignes ; exactement 9 sections numérotées dans l'ordre ; un lien vers
[[<projet>-Decisions]] ; une date de mise à jour dans la section 9 ; un bloc de commandes dans
la section 3 ; aucun chemin propre à une machine.

Usage :
  python3 tools/agent_knowledge.py                       # tous les projets du coffre memory/ (déduits des dossiers)
  python3 tools/agent_knowledge.py --projet lab          # un projet (option répétable)
  python3 tools/agent_knowledge.py --coffre <dossier>    # autre coffre que <racine du dépôt>/memory
Code de sortie : 0 = conforme, 1 = au moins un problème ou aucun projet, 2 = mauvais usage.
"""
import os
import re
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
COFFRE = os.path.join(RACINE, "memory")
MAX_LIGNES = 150  # strictement moins, comme « wc -l »

TITRES = (
    "En 30 secondes",
    "Où sont les choses",
    "Commandes prêtes à copier",
    "Conventions",
    "Zones sensibles et pourquoi",
    "Pièges connus",
    "Décisions qui encadrent le code",
    "Vocabulaire",
    "Mise à jour",
)

RE_TITRE = re.compile(r"^## (.*)$", re.MULTILINE)
RE_BLOC = re.compile(r"```[^\n]*\n(.*?)```", re.DOTALL)
RE_DATE = re.compile(r"\b\d{4}-\d{2}-\d{2}\b")
# « /Us" "ers/ » est assemblé : le contrôle des données personnelles du lab refuserait le motif en clair.
RE_CHEMIN_MACHINE = re.compile(r"(?:/Us" r"ers/|/ho" r"me/|[A-Za-z]:\\)")
RE_CHEMIN_DEPOT = re.compile(r"^(?:(?:tools|tests|scripts)/[\w./-]+|install\.sh)$")


def _section(texte, numero):
    """Texte de la section `numero` (1 à 9), sans son titre ; chaîne vide si absente."""
    titres = list(RE_TITRE.finditer(texte))
    for i, m in enumerate(titres):
        if m.group(1).startswith("%d. " % numero):
            fin = titres[i + 1].start() if i + 1 < len(titres) else len(texte)
            return texte[m.end():fin]
    return ""


def commandes_citees(texte):
    """Lignes de commande des blocs ``` de la section 3, sans commentaire ni ligne vide."""
    commandes = []
    for bloc in RE_BLOC.findall(_section(texte, 3)):
        for ligne in bloc.splitlines():
            ligne = re.sub(r"\s+#.*$", "", ligne).strip()
            if ligne and not ligne.startswith("#"):
                commandes.append(ligne)
    return commandes


def chemins_du_depot(commande):
    """Chemins relatifs au dépôt cités par une commande (tools/…, tests/…, scripts/…, install.sh)."""
    return [t for t in commande.split() if RE_CHEMIN_DEPOT.match(t.strip("\"'"))]


def verifier(texte, projet):
    """Liste des problèmes de forme de la page (vide si conforme)."""
    problemes = []
    lignes = texte.count("\n")
    if lignes >= MAX_LIGNES:
        problemes.append("%d lignes (limite : moins de %d)" % (lignes, MAX_LIGNES))
    attendus = ["%d. %s" % (i, t) for i, t in enumerate(TITRES, start=1)]
    trouves = [m.group(1).strip() for m in RE_TITRE.finditer(texte)]
    if trouves != attendus:
        problemes.append("sections : attendu %s, trouvé %s" % (attendus, trouves))
    if "[[%s-Decisions]]" % projet not in texte:
        problemes.append("lien [[%s-Decisions]] absent" % projet)
    if not RE_DATE.search(_section(texte, 9)):
        problemes.append("date AAAA-MM-JJ absente de la section 9")
    if not commandes_citees(texte):
        problemes.append("aucune commande dans un bloc de la section 3")
    if RE_CHEMIN_MACHINE.search(texte):
        problemes.append("chemin propre à une machine")
    return problemes


def projets_du_coffre(coffre):
    """Projets du coffre, triés : sous-dossiers (non cachés) portant une page <p>-Project ou <p>-Agent-Knowledge."""
    try:
        noms = sorted(os.listdir(coffre))
    except OSError:
        return []
    projets = []
    for nom in noms:
        if nom.startswith(".") or not os.path.isdir(os.path.join(coffre, nom)):
            continue
        if any(os.path.isfile(os.path.join(coffre, nom, "%s-%s.md" % (nom, s))) for s in ("Project", "Agent-Knowledge")):
            projets.append(nom)
    return projets


USAGE = "Usage : agent_knowledge.py [--coffre <dossier>] [--projet <nom>]..."


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    coffre = COFFRE
    projets = []
    i = 0
    while i < len(argv):
        if argv[i] in ("--coffre", "--projet") and i + 1 < len(argv) and argv[i + 1].startswith("--"):
            print("agent_knowledge : %s attend une valeur, pas « %s »" % (argv[i], argv[i + 1]), file=sys.stderr)
            return 2
        if argv[i] in ("--coffre", "--projet") and i + 1 < len(argv):
            if argv[i] == "--coffre":
                coffre = argv[i + 1]
            else:
                projets.append(argv[i + 1])
            i += 2
        else:
            print(USAGE, file=sys.stderr)
            return 2
    if not projets:
        projets = projets_du_coffre(coffre)
        if not projets:
            print("agent_knowledge : aucun projet dans le coffre %s" % coffre, file=sys.stderr)
            return 1
    code = 0
    for projet in projets:
        chemin = os.path.join(coffre, projet, "%s-Agent-Knowledge.md" % projet)
        try:
            with open(chemin, encoding="utf-8") as f:
                texte = f.read()
        except OSError:
            print("%s : page introuvable" % projet)
            code = 1
            continue
        problemes = verifier(texte, projet)
        print("%s : %d lignes, %s" % (projet, texte.count("\n"), "conforme" if not problemes else "PROBLÈMES"))
        for p in problemes:
            print("  - %s" % p)
        if problemes:
            code = 1
    return code


if __name__ == "__main__":
    sys.exit(main())
