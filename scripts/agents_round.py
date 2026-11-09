#!/usr/bin/env python3
"""Agents du lab pour un round : fabrique le JSON de l'option --agents de claude.

Usage : agents_round.py <dossier-agents> <projet|""> [--modele-projet M] [--modele-lab M]
Affiche sur la sortie standard {"nom": {"description", "prompt", "tools", "model"}, ...} (code 0).
Code 2 = mauvais usage.

  - agents généraux : <dossier>/*.md ; agents du projet du round : <dossier>/<projet>/*.md ;
    le général gagne sur un doublon (comme resolve-agent.sh) ; le sous-dossier d'un autre projet n'est jamais lu.
  - le nom d'un agent est le nom de son fichier (sans .md) ; l'en-tête (entre les deux premières lignes « --- »)
    donne description, tools (liste séparée par des virgules) et model ; le corps est le prompt.
  - modèle : agent > projet > lab (comme resolve-model.sh) ; « inherit » ou vide = niveau suivant ; aucun niveau =
    pas de champ model. Une valeur qui n'a pas la forme d'un nom de modèle est ignorée (avertissement sur stderr).
  - rien n'est interprété : les fichiers sont lus comme du texte et sérialisés en JSON (pas d'eval, pas de shell).
    Les liens symboliques sont ignorés (un agent ne peut pas pointer hors de agents/).
Ce fichier est dans scripts/ (et non tools/) parce que night.sh en dépend à l'exécution : scripts/ est livré
avec le lab, tools/ ne l'est pas.
"""
import argparse
import json
import os
import re
import sys

NOM_SIMPLE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
MODELE_VALIDE = re.compile(r"^[A-Za-z0-9][]A-Za-z0-9._:/[-]*$")
CLE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):[ \t]*(.*)$")


def nom_simple(s):
    return bool(NOM_SIMPLE.match(s or "")) and ".." not in s


def _sans_guillemets(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        v = v[1:-1]
    return v


def analyser(texte):
    """(en-tête dict, corps) d'un fichier agent. Sans en-tête : ({}, tout le texte)."""
    lignes = texte.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    if not lignes or lignes[0].rstrip() != "---":
        return {}, texte.replace("\r\n", "\n").strip()
    fin = None
    for i in range(1, len(lignes)):
        if lignes[i].rstrip() == "---":
            fin = i
            break
    if fin is None:
        return {}, texte.replace("\r\n", "\n").strip()
    entete = {}
    for ligne in lignes[1:fin]:
        m = CLE.match(ligne)
        if m:
            entete[m.group(1)] = _sans_guillemets(m.group(2))
    return entete, "\n".join(lignes[fin + 1:]).strip()


def modele_valide(v):
    return bool(MODELE_VALIDE.match(v or ""))


def resoudre_modele(modele_agent, modele_projet, modele_lab):
    """Premier niveau non vide et valide parmi agent, projet, lab ; None si aucun."""
    for niveau, v in (("agent", modele_agent), ("projet", modele_projet), ("lab", modele_lab)):
        v = (v or "").strip()
        if not v or v == "inherit":
            continue
        if modele_valide(v):
            return v
        sys.stderr.write("ATTENTION : modèle « %s » ignoré au niveau %s (caractères non admis)\n" % (v, niveau))
    return None


def _fichiers_md(dossier):
    """{nom: chemin} des fichiers NOM.md réguliers (ni lien symbolique ni nom étrange) d'un dossier."""
    res = {}
    if not os.path.isdir(dossier) or os.path.islink(dossier):
        return res
    for f in sorted(os.listdir(dossier)):
        chemin = os.path.join(dossier, f)
        if not f.endswith(".md") or not os.path.isfile(chemin) or os.path.islink(chemin):
            continue
        nom = f[:-3]
        if nom_simple(nom):
            res[nom] = chemin
    return res


def construire_agents(dossier, projet, modele_projet, modele_lab):
    fichiers = {}
    if nom_simple(projet) and os.path.isdir(os.path.join(dossier, projet)):
        fichiers.update(_fichiers_md(os.path.join(dossier, projet)))
    fichiers.update(_fichiers_md(dossier))      # le général écrase le projet
    agents = {}
    for nom in sorted(fichiers):
        with open(fichiers[nom], encoding="utf-8", newline="") as f:
            entete, corps = analyser(f.read())
        agent = {"description": entete.get("description") or nom, "prompt": corps}
        outils = [t.strip() for t in entete.get("tools", "").split(",") if t.strip()]
        if outils:
            agent["tools"] = outils
        modele = resoudre_modele(entete.get("model", ""), modele_projet, modele_lab)
        if modele:
            agent["model"] = modele
        agents[nom] = agent
    return agents


def main(argv=None):
    p = argparse.ArgumentParser(description="JSON de --agents pour un round")
    p.add_argument("dossier")
    p.add_argument("projet")
    p.add_argument("--modele-projet", default="")
    p.add_argument("--modele-lab", default="")
    try:
        a = p.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    json.dump(construire_agents(a.dossier, a.projet, a.modele_projet, a.modele_lab), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
