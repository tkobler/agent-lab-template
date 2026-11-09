---
name: direct-session
description: Utiliser quand l'utilisateur veut travailler lui-même avec Claude, en direct, sur un projet (« ouvre une session sur X », « je veux bosser sur X »), ou fermer une telle session.
---

# Session de travail directe

1. Projet : parmi `ls config/projects/`. Sujet en quelques mots → branche `claude/direct-<sujet>`
   (ou une branche claude/* existante et non mergée pour continuer un travail).
2. Si un round tourne ou est prévu cette nuit sur la même branche, préviens : une branche ne peut être
   ouverte que dans une seule copie à la fois.
3. Lance `scripts/direct-session.sh <projet> <branche>`.
4. Dis à l'utilisateur : ouvre « Direct · <projet> » dans la liste des sessions de l'app Claude.
   Rappelle-lui : le travail se fait sur <branche> ; à la fin, demander à cette session de commiter,
   de pousser (`git push -u origin <branche>`) et d'ouvrir une PR (`gh pr create --draft`).
5. Fermer : `scripts/direct-session.sh --close <projet>` (vérifie d'abord avec l'utilisateur que
   le travail est commité : `git -C @WORKTREES@/<projet>-direct status`).
6. Note l'ouverture et la fermeture dans `memory/lab/lab-Running.md` (section « Sessions directes ouvertes »).
