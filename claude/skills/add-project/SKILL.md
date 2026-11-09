---
name: add-project
description: Utiliser quand l'utilisateur veut ajouter un dépôt GitHub existant au lab, ou créer un projet neuf (nouveau dépôt), pour que les agents puissent y travailler.
---

# Ajouter ou créer un projet

1. Demande, une question à la fois : dépôt existant ou projet neuf ? Puis un nom court (minuscules, tirets).
   Ton compte GitHub : `gh api user --jq .login`.
2. Dépôt existant : demande son nom GitHub (compte/dépôt) et vérifie l'accès : `gh repo view <compte/dépôt>`.
   Projet neuf : demande en une phrase à quoi il sert, puis
   `gh repo create <compte>/<nom> --private --add-readme --description "<phrase>"` (autorisation attendue).
3. Clone : `gh repo clone <compte/dépôt> @PROJETS@/<nom>` (autorisation attendue).
   Branche de base : celle par défaut (`gh repo view <compte/dépôt> --json defaultBranchRef --jq .defaultBranchRef.name`).
4. Garde-fous : `scripts/install-hooks.sh @PROJETS@/<nom>`.
5. Propose de protéger la branche de base sur GitHub (avec accord) :
   `gh api -X PUT repos/<compte/dépôt>/branches/<base>/protection --input templates/protection-main.json`
   Erreur 403 = non disponible pour un dépôt privé avec l'offre gratuite : dis-le simplement et continue.
6. Explore le dépôt en lecture : README, CLAUDE.md, fichiers de dépendances (package.json, pyproject.toml,
   Cargo.toml, go.mod...), Makefile, config CI, .gitignore. Déduis la stack et les commandes utiles.
   Projet neuf : demande la stack souhaitée et l'objectif de départ.
7. Rédige la fiche `config/projects/<nom>.md` : en une phrase, stack, commandes, conventions,
   zones sensibles, notes du manageur. Fais valider les zones sensibles par l'utilisateur.
8. Rédige `config/projects/<nom>.env` :
   REPO_PATH="@PROJETS@/<nom>"
   GITHUB="<compte/dépôt>"
   BRANCHE_BASE="<base>"
   OUTILS_EXTRA="Bash(<commande test>*),Bash(<commande lint>*)"
   COMMANDES_TEST="<commande test exacte>|<commande lint exacte>"
   Montre la liste OUTILS_EXTRA et explique que ces commandes seront lancées sans confirmation par les agents.
   N'y mets jamais de commande de déploiement, de publication, gh, ni sudo.
   COMMANDES_TEST (facultative) liste les commandes de test EXACTES, séparées par `|`, en chemin relatif depuis la racine
   du worktree (`bash tests/x.sh`, pas de chemin absolu), une commande simple par entrée (ni `&&`, ni `;`, ni redirection).
   `scripts/night.sh 1 --check` et `install.sh` (à la fin, via `scripts/night.sh fiches`) vérifient que chacune est couverte par
   OUTILS_EXTRA et non interdite ; sinon « PERMISSION MANQUANTE : <commande> » : corrige OUTILS_EXTRA avant la première nuit.
   Pour la vérifier en vrai (session claude courte, vraies permissions, après un premier round) : `scripts/night.sh --essai <nom>`,
   à lancer seulement si l'utilisateur le demande (il consomme du quota).
9. Crée les pages du projet dans la mémoire : lance `scripts/add-project-memory.sh <nom>` (autorisation attendue).
   Il crée `memory/<nom>/` depuis les gabarits `note-*.empty.md` du dossier templates : `<nom>-Project` (but, vision, structure,
   « Où en est-on »), `<nom>-Agent-Knowledge` (contexte condensé que chaque round lit en premier), `<nom>-Decisions`
   et `<nom>-Log`, et ajoute le projet au tableau de `memory/Home.md`. Il n'écrase jamais une note existante.
   Remplis ensuite `<nom>-Project` et `<nom>-Agent-Knowledge` d'après la fiche. Ce sont des pages privées : jamais
   de secret dedans.
10. Vérifie que le .gitignore du dépôt exclut les secrets, les dossiers de build et .DS_Store ; sinon propose
    une première tâche pour le corriger.
11. Si le dépôt n'a pas de CLAUDE.md, propose une tâche [codeur] sur une branche claude/claude-md pour en rédiger un.
12. Vérifie que les outils de la stack sont installés sur le Mac (node, python, etc.) ; sinon donne la commande
    brew correspondante et rappelle qu'elle demande une validation.
13. Note le projet dans la section « Où en est-on » de `memory/<nom>/<nom>-Project.md` et dans `<nom>-Decisions`
    (date, projet, décision d'ajouter le projet, raison), puis propose une première tâche simple, à lancer tout de suite
    (run-now) ou cette nuit (plan-night).
