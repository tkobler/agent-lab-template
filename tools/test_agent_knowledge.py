"""Tests des pages <projet>-Agent-Knowledge : forme (verifier), extraction des commandes, projets déduits du coffre.

Fichier livré dans le lab publiable : il ne dépend d'aucun coffre réel ni d'aucun nom de projet (coffres factices
dans des dossiers temporaires). Les tests sur les pages réelles du lab en service sont dans
tools/test_agent_knowledge_coffre.py (non livré).

Lancer : python3 -m unittest   (depuis la racine du dépôt)
"""
import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agent_knowledge as ak  # noqa: E402

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def page_valide(projet="demo", extra_fin=""):
    """Une page minimale conforme, construite à partir des titres officiels."""
    lignes = ["# %s-Agent-Knowledge" % projet, ""]
    for numero, titre in enumerate(ak.TITRES, start=1):
        lignes += ["## %d. %s" % (numero, titre), "texte", ""]
        if numero == 3:
            lignes[-2:-1] = ["```", "python3 -m unittest   # tous les tests", "```"]
        if numero == 7:
            lignes[-2:-1] = ["Voir [[%s-Decisions]]." % projet]
        if numero == 9:
            lignes[-2:-1] = ["Mis à jour le 2026-10-20."]
    return "\n".join(lignes) + "\n" + extra_fin


def ecrire(chemin, texte):
    os.makedirs(os.path.dirname(chemin), exist_ok=True)
    with open(chemin, "w", encoding="utf-8") as f:
        f.write(texte)


def lancer(argv):
    """main(argv) avec la sortie capturée : (code, sortie standard, sortie d'erreur)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = ak.main(argv)
    return code, out.getvalue(), err.getvalue()


class TestVerifierForme(unittest.TestCase):
    def test_page_conforme_sans_probleme(self):
        self.assertEqual(ak.verifier(page_valide(), "demo"), [])

    def test_page_vide(self):
        self.assertTrue(ak.verifier("", "demo"))

    def test_149_lignes_acceptees_150_refusees(self):
        base = page_valide()
        n = base.count("\n")
        ok = base + "x\n" * (149 - n)
        self.assertEqual(ok.count("\n"), 149)
        self.assertEqual(ak.verifier(ok, "demo"), [])
        trop = base + "x\n" * (150 - n)
        self.assertEqual(trop.count("\n"), 150)
        self.assertTrue(any("150" in p for p in ak.verifier(trop, "demo")))

    def test_section_manquante(self):
        texte = page_valide().replace("## 6. %s" % ak.TITRES[5], "### 6. %s" % ak.TITRES[5])
        self.assertTrue(any("section" in p for p in ak.verifier(texte, "demo")))

    def test_sections_dans_le_desordre(self):
        a, b = "## 4. %s" % ak.TITRES[3], "## 5. %s" % ak.TITRES[4]
        texte = page_valide().replace(a, "@@").replace(b, a).replace("@@", b)
        self.assertTrue(ak.verifier(texte, "demo"))

    def test_dixieme_section_refusee(self):
        texte = page_valide(extra_fin="## 10. En trop\n")
        self.assertTrue(any("section" in p for p in ak.verifier(texte, "demo")))

    def test_lien_decisions_obligatoire_et_du_bon_projet(self):
        texte = page_valide().replace("[[demo-Decisions]]", "[[autre-Decisions]]")
        self.assertTrue(any("Decisions" in p for p in ak.verifier(texte, "demo")))

    def test_date_obligatoire_dans_la_section_9(self):
        texte = page_valide().replace("2026-10-20", "bientôt")
        self.assertTrue(any("date" in p for p in ak.verifier(texte, "demo")))

    def test_date_hors_section_9_ne_compte_pas(self):
        texte = page_valide().replace("2026-10-20", "bientôt").replace("texte", "le 2026-10-20", 1)
        self.assertTrue(any("date" in p for p in ak.verifier(texte, "demo")))

    def test_bloc_de_commandes_obligatoire_en_section_3(self):
        texte = page_valide().replace("```", "")
        self.assertTrue(any("commande" in p for p in ak.verifier(texte, "demo")))

    def test_chemin_de_machine_refuse(self):
        texte = page_valide(extra_fin="voir /Us" "ers/quelquun/x\n")
        self.assertTrue(any("chemin" in p for p in ak.verifier(texte, "demo")))
        texte = page_valide(extra_fin="voir /ho" "me/quelquun/x\n")
        self.assertTrue(any("chemin" in p for p in ak.verifier(texte, "demo")))


class TestCommandes(unittest.TestCase):
    def test_extrait_les_lignes_du_bloc_sans_commentaire(self):
        texte = page_valide().replace("python3 -m unittest   # tous les tests",
                                      "python3 -m unittest   # tous\n\n# seul commentaire\nbash a.sh x")
        self.assertEqual(ak.commandes_citees(texte), ["python3 -m unittest", "bash a.sh x"])

    def test_aucun_bloc_aucune_commande(self):
        self.assertEqual(ak.commandes_citees("# titre\n"), [])

    def test_seule_la_section_3_compte(self):
        texte = page_valide(extra_fin="```\nrm -rf x\n```\n")
        self.assertEqual(ak.commandes_citees(texte), ["python3 -m unittest"])

    def test_chemins_du_depot_reconnus(self):
        self.assertEqual(ak.chemins_du_depot("python3 tools/controle_coffre.py --lister"),
                         ["tools/controle_coffre.py"])
        self.assertEqual(ak.chemins_du_depot("bash install.sh <dossier>"), ["install.sh"])
        # ancien nom de script, assemblé : aucun ancien nom en clair dans le dépôt
        ancien = "<dossier>/scripts/" + "nu" "it.sh 1 --" "veri" "fier"
        self.assertEqual(ak.chemins_du_depot(ancien), [])
        self.assertEqual(ak.chemins_du_depot("git status"), [])
        self.assertEqual(ak.chemins_du_depot("bash tests/lancer-tous-les-tests.sh"),
                         ["tests/lancer-tous-les-tests.sh"])

    def test_chemin_d_un_script_zsh(self):
        self.assertEqual(ak.chemins_du_depot("zsh tools/run-watches.zsh un-arg"), ["tools/run-watches.zsh"])


class TestProjetsDuCoffre(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.coffre = os.path.join(self.tmp.name, "memory")

    def test_coffre_absent_liste_vide(self):
        self.assertEqual(ak.projets_du_coffre(os.path.join(self.tmp.name, "inexistant")), [])

    def test_coffre_vide_liste_vide(self):
        os.makedirs(self.coffre)
        self.assertEqual(ak.projets_du_coffre(self.coffre), [])

    def test_projets_tries_deduits_des_dossiers(self):
        for p in ("zeta", "alpha", "lab"):
            ecrire(os.path.join(self.coffre, p, "%s-Project.md" % p), "x")
        self.assertEqual(ak.projets_du_coffre(self.coffre), ["alpha", "lab", "zeta"])

    def test_projet_reconnu_par_sa_page_agent_knowledge_seule(self):
        ecrire(os.path.join(self.coffre, "solo", "solo-Agent-Knowledge.md"), "x")
        self.assertEqual(ak.projets_du_coffre(self.coffre), ["solo"])

    def test_dossiers_et_fichiers_qui_ne_sont_pas_des_projets_ignores(self):
        ecrire(os.path.join(self.coffre, "Home.md"), "x")                      # fichier à la racine
        ecrire(os.path.join(self.coffre, ".obsidian", "app.json"), "{}")       # dossier caché
        ecrire(os.path.join(self.coffre, "notes", "vrac.md"), "x")             # dossier sans page de projet
        ecrire(os.path.join(self.coffre, "demo", "demo-Project.md"), "x")
        self.assertEqual(ak.projets_du_coffre(self.coffre), ["demo"])


class TestMain(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.coffre = os.path.join(self.tmp.name, "memory")

    def page(self, projet, texte):
        ecrire(os.path.join(self.coffre, projet, "%s-Agent-Knowledge.md" % projet), texte)

    def test_mauvais_usage_code_2(self):
        self.assertEqual(lancer(["--inconnu"])[0], 2)

    def test_option_sans_valeur_code_2(self):
        self.assertEqual(lancer(["--coffre", self.coffre, "--projet"])[0], 2)
        self.assertEqual(lancer(["--coffre"])[0], 2)

    def test_projets_deduits_tous_conformes_code_0(self):
        self.page("alpha", page_valide("alpha"))
        self.page("beta", page_valide("beta"))
        code, sortie, _ = lancer(["--coffre", self.coffre])
        self.assertEqual(code, 0, sortie)
        self.assertIn("alpha : ", sortie)
        self.assertIn("beta : ", sortie)

    def test_un_projet_non_conforme_code_1_et_problemes_listes(self):
        self.page("alpha", page_valide("alpha"))
        self.page("beta", "# vide\n")
        code, sortie, _ = lancer(["--coffre", self.coffre])
        self.assertEqual(code, 1)
        self.assertIn("beta : ", sortie)
        self.assertIn("PROBLÈMES", sortie)

    def test_projet_en_argument_ne_controle_que_lui(self):
        self.page("alpha", page_valide("alpha"))
        self.page("beta", "# vide\n")
        code, sortie, _ = lancer(["--coffre", self.coffre, "--projet", "alpha"])
        self.assertEqual(code, 0, sortie)
        self.assertNotIn("beta", sortie)

    def test_plusieurs_projets_en_argument(self):
        self.page("alpha", page_valide("alpha"))
        self.page("beta", page_valide("beta"))
        self.page("gamma", "# vide\n")
        code, sortie, _ = lancer(["--coffre", self.coffre, "--projet", "alpha", "--projet", "beta"])
        self.assertEqual(code, 0, sortie)
        self.assertNotIn("gamma", sortie)

    def test_projet_sans_page_code_1(self):
        os.makedirs(self.coffre)
        code, sortie, _ = lancer(["--coffre", self.coffre, "--projet", "projet-qui-n-existe-pas"])
        self.assertEqual(code, 1)
        self.assertIn("introuvable", sortie)

    def test_projet_avec_dossier_mais_sans_page_code_1(self):
        ecrire(os.path.join(self.coffre, "demi", "demi-Project.md"), "x")
        code, sortie, _ = lancer(["--coffre", self.coffre])
        self.assertEqual(code, 1)
        self.assertIn("demi : page introuvable", sortie)

    def test_coffre_sans_projet_code_1_avec_message(self):
        os.makedirs(self.coffre)
        code, _, err = lancer(["--coffre", self.coffre])
        self.assertEqual(code, 1)
        self.assertIn("aucun projet", err)

    def test_coffre_absent_code_1(self):
        code, _, err = lancer(["--coffre", os.path.join(self.tmp.name, "inexistant")])
        self.assertEqual(code, 1)
        self.assertIn("aucun projet", err)

    def test_coffre_en_option_suivi_d_un_drapeau_erreur_claire(self):
        code, _, err = lancer(["--coffre", "--projet", "x"])
        self.assertEqual(code, 2)
        self.assertIn("--coffre", err)

    def test_ne_connait_que_les_projets_du_coffre_donne(self):
        # Noms inventés : la sortie ne cite que ces projets, aucune liste en dur dans le module.
        self.page("zz-un", page_valide("zz-un"))
        self.page("zz-deux", page_valide("zz-deux"))
        code, sortie, _ = lancer(["--coffre", self.coffre])
        self.assertEqual(code, 0, sortie)
        self.assertEqual([l.split(" : ")[0] for l in sortie.splitlines()], ["zz-deux", "zz-un"])

    def test_le_module_ne_contient_aucun_chemin_de_machine(self):
        import re
        with open(ak.__file__, encoding="utf-8") as f:
            source = f.read()
        # motifs sans le chemin en clair : racine des comptes, dossier personnel, ~/
        self.assertIsNone(re.search(r"/[U]sers/|/[h]ome/|~/", source))

    def test_coffre_par_defaut_est_memory_a_la_racine_du_depot(self):
        self.assertEqual(ak.COFFRE, os.path.join(RACINE, "memory"))


if __name__ == "__main__":
    unittest.main()
