---
name: create-agent
description: Utiliser quand l'utilisateur veut un nouveau type d'agent (ex. rédacteur de docs, testeur, traducteur, analyste de données) ou modifier un agent existant.
---

# Créer ou modifier un agent

1. Lis les agents existants, généraux (agents/*.md) et propres à un projet (agents/<projet>/*.md) :
   vérifie qu'aucun ne couvre déjà le besoin.
   Si un agent existant suffit avec un ajustement, propose plutôt de le modifier.
   Demande aussi si l'agent est général (utile à tous les projets) ou propre à un projet (il parle de son
   langage, de ses outils, de ses données) : un agent propre à un projet va dans son sous-dossier.
2. Clarifie avec l'utilisateur, une question à la fois :
   - la mission en une phrase et ce qui est hors de sa mission,
   - ce qu'il produit et où (code commité, note dans docs/..., fichiers de test...),
   - ce qu'il doit absolument vérifier avant de rendre son travail,
   - s'il a besoin du web.
3. Choisis le nom : minuscules, tirets, parlant. Ce nom sera le tag [nom] dans les tâches.
   Un tag est unique : si agents/<nom>.md (général) et agents/<projet>/<nom>.md existent tous deux, le général gagne
   (`night.sh` avertit) ; ne crée donc pas un agent de projet qui porte le nom d'un agent général.
4. Choisis les outils au strict minimum :
   - lecture seule : Read, Glob, Grep
   - écrit des fichiers : + Edit, Write
   - lance des commandes : + Bash (les commandes réellement autorisées restent limitées
     par `scripts/night.sh` et OUTILS_EXTRA)
   - recherche : + WebSearch, WebFetch
5. Écris agents/<nom>.md (agent général) ou agents/<projet>/<nom>.md (agent propre à ce projet, utilisable
   seulement dans les rounds de ce projet ; ces fichiers ne sont jamais exportés dans le template). Le champ
   `name:` reste le nom seul, sans le projet. Contenu :
   ---
   name: <nom>
   description: <quand l'utiliser — commencer par ce qu'il fait, finir par « À utiliser pour toute tâche [<nom>]. »>
   tools: <liste>
   model: sonnet
   ---
   puis les sections : rôle, méthode (étapes numérotées), règles (reprendre les règles de sécurité
   de codeur.md : branche courante, pas de push, pas de contournement), compte-rendu attendu.
6. Si l'agent a besoin de nouvelles commandes, indique quelles lignes ajouter à OUTILS_EXTRA
   des projets concernés (`config/projects/<projet>.env`) et demande l'accord.
7. Si l'agent produit du code, rappelle que le chef de nuit le fera relire par relecteur
   seulement s'il s'agit d'une tâche [codeur]. Propose d'ajuster prompts/night.md si l'utilisateur veut
   une relecture pour ce nouvel agent aussi.
8. Propose une petite tâche de test (maintenant avec run-now, ou cette nuit avec plan-night) et note la création
   de l'agent dans `memory/lab/lab-Decisions.md` (section « Décisions prises », date, décision, raison).
   Ajoute-le aussi à la liste des agents de `memory/lab/lab-Agent-Knowledge.md`.
