# <projet> : l'équipe d'agents

[[Home]] · [[<projet>/<projet>-Project]] · [[<projet>/<projet>-Running]] · [[<projet>/<projet>-Decisions]]

Résumé pour l'utilisateur, tenu par le manageur. Ce n'est pas une copie : les originaux sont `agents/<nom>.md` (le nom du fichier = le tag utilisable dans une tâche) et `.claude/skills/<nom>/SKILL.md`. À mettre à jour à chaque agent ou skill ajouté ou modifié (skill create-agent).

Modèle : `inherit` = celui du projet, sinon celui du lab.

## Agents de base (tous les projets)
- **chercheur** (inherit) : recherche documentée (comparaison de solutions, veille, étude d'une librairie), produit une note écrite dans le dépôt.
- **codeur** (inherit) : implémente une tâche de code précise (fonctionnalité, correctif, refactor, tests), tests d'abord.
- **relecteur** (inherit) : relit le diff du round et liste les problèmes par gravité, sans rien modifier. Après chaque [codeur].
- **testeur** (inherit) : vérifie de bout en bout qu'un outil donne le bon résultat sur des données d'exemple, sans toucher au code, et écrit le protocole de test manuel. En général après un [codeur].

## Agents propres à un projet
(aucun pour l'instant : `agents/<projet>/`, créés avec la skill create-agent)

## Skills du manageur (ce qu'il faut me dire)
- **morning-review** : « fais la revue », « qu'est-ce qui a été fait ? ». Bilan des rounds, décisions à prendre, mise à jour de la mémoire.
- **plan-night** : « cette nuit il faudrait… », « prépare la nuit ». Construit `config/TASKS.md` avec toi, l'écrit après ta validation.
- **run-now** : « lance-le maintenant ». Round immédiat de jour (même quota qu'une nuit), après ton accord.
- **add-project** : « ajoute le dépôt X », « crée un projet ». Clone, fiche projet, pages de mémoire.
- **direct-session** : « je veux bosser sur X », « ferme la session ». Session de travail directe avec Claude sur un projet.
- **create-agent** : « il me faudrait un agent qui… ». Crée ou modifie un type d'agent.
- **night-diagnosis** : « le round a raté », « pourquoi pas de rapport ? ». Comprend un round en échec.
