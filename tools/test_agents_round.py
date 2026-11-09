"""Tests de scripts/agents_round.py : agents du lab fournis à claude par --agents (JSON).

Lancer : python3 -m unittest   (depuis la racine du dépôt)
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RACINE, "scripts"))

import agents_round as ar  # noqa: E402

OUTIL = os.path.join(RACINE, "scripts", "agents_round.py")


def agent(description="Décrit.", tools="Read, Grep", model="inherit", corps="Corps.\n", extra=""):
    entete = ["---", "name: x", "description: %s" % description]
    if tools is not None:
        entete.append("tools: %s" % tools)
    if model is not None:
        entete.append("model: %s" % model)
    return "\n".join(entete) + "\n" + extra + "---\n\n" + corps


class Base(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.dir = self._tmp.name

    def ecrire(self, chemin, texte):
        complet = os.path.join(self.dir, chemin)
        os.makedirs(os.path.dirname(complet), exist_ok=True)
        with open(complet, "w", encoding="utf-8", newline="") as f:
            f.write(texte)


class TestAnalyse(Base):
    def test_champs_et_prompt(self):
        self.ecrire("codeur.md", agent(description="Fait du code.", tools="Read, Glob, Bash", corps="Tu es codeur.\n\n## Règles\n- a\n"))
        r = ar.construire_agents(self.dir, "", "", "")
        self.assertEqual(list(r), ["codeur"])
        self.assertEqual(r["codeur"]["description"], "Fait du code.")
        self.assertEqual(r["codeur"]["tools"], ["Read", "Glob", "Bash"])
        self.assertEqual(r["codeur"]["prompt"], "Tu es codeur.\n\n## Règles\n- a")

    def test_nom_vient_du_fichier_pas_du_champ_name(self):
        self.ecrire("vrai-nom.md", agent())
        self.assertEqual(list(ar.construire_agents(self.dir, "", "", "")), ["vrai-nom"])

    def test_tools_absent_pas_de_champ_tools(self):
        self.ecrire("a.md", agent(tools=None))
        self.assertNotIn("tools", ar.construire_agents(self.dir, "", "", "")["a"])

    def test_tools_vide_pas_de_champ_tools(self):
        self.ecrire("a.md", agent(tools=""))
        self.assertNotIn("tools", ar.construire_agents(self.dir, "", "", "")["a"])

    def test_guillemets_autour_de_la_description(self):
        self.ecrire("a.md", agent(description='"Entre guillemets : oui"'))
        self.assertEqual(ar.construire_agents(self.dir, "", "", "")["a"]["description"], "Entre guillemets : oui")

    def test_fins_de_ligne_windows(self):
        self.ecrire("a.md", agent(corps="Ligne 1\nLigne 2\n").replace("\n", "\r\n"))
        r = ar.construire_agents(self.dir, "", "", "")["a"]
        self.assertEqual(r["description"], "Décrit.")
        self.assertEqual(r["tools"], ["Read", "Grep"])
        self.assertEqual(r["prompt"], "Ligne 1\nLigne 2")

    def test_sans_en_tete_le_fichier_est_le_prompt(self):
        self.ecrire("nu.md", "Juste un prompt.\n")
        r = ar.construire_agents(self.dir, "", "", "")["nu"]
        self.assertEqual(r["prompt"], "Juste un prompt.")
        self.assertEqual(r["description"], "nu")     # claude exige une description

    def test_description_absente_remplacee_par_le_nom(self):
        self.ecrire("a.md", "---\nname: a\n---\nCorps\n")
        self.assertEqual(ar.construire_agents(self.dir, "", "", "")["a"]["description"], "a")

    def test_corps_vide(self):
        self.ecrire("a.md", "---\nname: a\ndescription: d\n---\n")
        self.assertEqual(ar.construire_agents(self.dir, "", "", "")["a"]["prompt"], "")

    def test_ligne_horizontale_dans_le_corps_ne_coupe_pas(self):
        self.ecrire("a.md", agent(corps="Avant\n---\nAprès\n"))
        self.assertEqual(ar.construire_agents(self.dir, "", "", "")["a"]["prompt"], "Avant\n---\nAprès")

    def test_fichiers_non_md_et_noms_invalides_ignores(self):
        self.ecrire("notes.txt", "x")
        self.ecrire(".cache.md", agent())
        self.ecrire("a b.md", agent())
        self.ecrire("bon.md", agent())
        self.assertEqual(list(ar.construire_agents(self.dir, "", "", "")), ["bon"])

    def test_dossier_absent(self):
        self.assertEqual(ar.construire_agents(os.path.join(self.dir, "rien"), "p", "", ""), {})

    def test_json_sans_injection(self):
        # Du texte qui ressemble à du shell ou du JSON reste une simple chaîne.
        self.ecrire("a.md", agent(description='"; rm -rf / #', corps='$(touch x) `y` "}\n'))
        r = json.loads(json.dumps(ar.construire_agents(self.dir, "", "", "")))
        self.assertEqual(r["a"]["prompt"], '$(touch x) `y` "}')


class TestProjetEtDoublons(Base):
    def test_agents_de_projet_ajoutes(self):
        self.ecrire("codeur.md", agent())
        self.ecrire("demo/analyste.md", agent(corps="Analyse.\n"))
        r = ar.construire_agents(self.dir, "demo", "", "")
        self.assertEqual(sorted(r), ["analyste", "codeur"])
        self.assertEqual(r["analyste"]["prompt"], "Analyse.")

    def test_general_gagne_sur_doublon(self):
        self.ecrire("codeur.md", agent(corps="GENERAL\n"))
        self.ecrire("demo/codeur.md", agent(corps="PROJET\n"))
        r = ar.construire_agents(self.dir, "demo", "", "")
        self.assertEqual(r["codeur"]["prompt"], "GENERAL")

    def test_autre_projet_jamais(self):
        self.ecrire("codeur.md", agent())
        self.ecrire("autre/secret.md", agent())
        self.assertEqual(list(ar.construire_agents(self.dir, "demo", "", "")), ["codeur"])

    def test_sans_projet_seulement_les_generaux(self):
        self.ecrire("codeur.md", agent())
        self.ecrire("demo/x.md", agent())
        self.assertEqual(list(ar.construire_agents(self.dir, "", "", "")), ["codeur"])

    def test_projet_invalide_refuse(self):
        self.ecrire("codeur.md", agent())
        self.ecrire("sub/x.md", agent())
        for mauvais in ("..", "../agents", "a/b", "sub/.."):
            self.assertEqual(list(ar.construire_agents(self.dir, mauvais, "", "")), ["codeur"], mauvais)

    def test_lien_symbolique_hors_de_agents_ignore(self):
        with tempfile.TemporaryDirectory() as dehors:
            with open(os.path.join(dehors, "evil.md"), "w") as f:
                f.write(agent())
            os.symlink(os.path.join(dehors, "evil.md"), os.path.join(self.dir, "evil.md"))
            self.assertEqual(ar.construire_agents(self.dir, "", "", ""), {})


class TestModele(Base):
    def test_modele_de_l_agent_prioritaire(self):
        self.ecrire("a.md", agent(model="haiku"))
        self.assertEqual(ar.construire_agents(self.dir, "", "opus", "sonnet")["a"]["model"], "haiku")

    def test_inherit_prend_le_projet(self):
        self.ecrire("a.md", agent(model="inherit"))
        self.assertEqual(ar.construire_agents(self.dir, "", "opus", "sonnet")["a"]["model"], "opus")

    def test_inherit_puis_lab(self):
        self.ecrire("a.md", agent(model="inherit"))
        self.assertEqual(ar.construire_agents(self.dir, "", "", "sonnet")["a"]["model"], "sonnet")

    def test_inherit_et_rien_pas_de_champ_model(self):
        self.ecrire("a.md", agent(model="inherit"))
        self.assertNotIn("model", ar.construire_agents(self.dir, "", "", "")["a"])

    def test_model_absent_se_comporte_comme_inherit(self):
        self.ecrire("a.md", agent(model=None))
        self.assertNotIn("model", ar.construire_agents(self.dir, "", "", "")["a"])
        self.assertEqual(ar.construire_agents(self.dir, "", "opus", "")["a"]["model"], "opus")

    def test_valeur_invalide_ignoree_niveau_suivant(self):
        self.ecrire("a.md", agent(model="bad model;x"))
        self.assertEqual(ar.construire_agents(self.dir, "", "$(x)", "sonnet")["a"]["model"], "sonnet")

    def test_modele_avec_crochets(self):
        self.ecrire("a.md", agent(model="opus[1m]"))
        self.assertEqual(ar.construire_agents(self.dir, "", "", "")["a"]["model"], "opus[1m]")

    def test_modele_agent_de_projet(self):
        self.ecrire("demo/b.md", agent(model="sonnet"))
        self.assertEqual(ar.construire_agents(self.dir, "demo", "opus", "")["b"]["model"], "sonnet")


class TestAgentsReels(unittest.TestCase):
    """Extrait réel : les agents du dépôt."""

    def test_agents_generaux_du_depot(self):
        r = ar.construire_agents(os.path.join(RACINE, "agents"), "", "", "")
        for nom in ("chercheur", "codeur", "relecteur", "testeur"):
            self.assertIn(nom, r)
            self.assertTrue(r[nom]["prompt"])
            self.assertTrue(r[nom]["description"])
            self.assertNotIn("model", r[nom])       # model: inherit, aucun réglage
        self.assertEqual(r["codeur"]["tools"], ["Read", "Glob", "Grep", "Edit", "Write", "Bash", "TodoWrite"])
        self.assertTrue(r["codeur"]["prompt"].startswith("Tu es un développeur senior"))


class TestAgentDeProjetFactice(Base):
    """Agent propre à un projet (agents/<projet>/), avec des noms inventés."""

    def test_agent_de_projet_charge_seulement_pour_son_projet(self):
        self.ecrire("codeur.md", agent())
        self.ecrire("projet-demo/agent-demo.md", agent(model="sonnet"))
        avec = ar.construire_agents(self.dir, "projet-demo", "", "")
        self.assertEqual(avec["agent-demo"]["model"], "sonnet")
        self.assertIn("codeur", avec)
        self.assertNotIn("agent-demo", ar.construire_agents(self.dir, "", "", ""))
        self.assertNotIn("agent-demo", ar.construire_agents(self.dir, "autre-projet", "", ""))


class TestCommande(Base):
    def lancer(self, *args):
        return subprocess.run([sys.executable, OUTIL] + list(args), capture_output=True, text=True)

    def test_sortie_json(self):
        self.ecrire("a.md", agent(model="inherit"))
        p = self.lancer(self.dir, "", "--modele-projet", "opus", "--modele-lab", "sonnet")
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(json.loads(p.stdout)["a"]["model"], "opus")

    def test_dossier_vide_donne_objet_vide(self):
        p = self.lancer(self.dir, "demo")
        self.assertEqual(p.returncode, 0)
        self.assertEqual(json.loads(p.stdout), {})

    def test_mauvais_usage(self):
        self.assertEqual(self.lancer().returncode, 2)


if __name__ == "__main__":
    unittest.main()
