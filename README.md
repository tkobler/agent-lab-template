# agent-lab : une équipe d'agents IA qui travaille la nuit

## 1. Ce que fait le lab

- Le soir, vous validez avec le **manageur** (une session Claude Code qui connaît le lab) les tâches de la nuit.
- La nuit, des LaunchAgents lancent des **rounds** : un projet et une branche `claude/<sujet>` par round, tests écrits
  avant le code, petits commits, PR en brouillon, rapport dans `reports/`.
- Le matin, le manageur résume les rapports, liste les PR prêtes et les questions des agents.
- Vous seul fusionnez les PR sur GitHub : un agent ne pousse jamais sur la branche principale.
- Le manageur ne code pas : il prépare, lance, résume et tient la mémoire (`memory/`, que les agents lisent sans écrire).

## 2. Prérequis

- macOS (LaunchAgents, `launchctl`, `caffeinate`) et git.
- Un abonnement Claude (les rounds consomment son quota) et le CLI [Claude Code](https://claude.com/claude-code)
  (commande `claude`), déjà connecté : lancez `claude` une fois et connectez-vous.
- `gh` (GitHub CLI) connecté à votre compte : `gh auth login`.
- Via Homebrew : `tmux`, `flock` (verrou des rounds) et `coreutils` (`gtimeout`).
- Optionnel : Obsidian, pour lire `memory/` comme un coffre de notes.

```
brew install gh tmux flock coreutils
```

## 3. Installation pas à pas

Le lab tourne dans le clone du dépôt (ici `~/agent-lab`). Remplacez `<URL-DU-DEPOT>` par l'adresse reçue.

```
git clone <URL-DU-DEPOT> ~/agent-lab
cd ~/agent-lab
bash install.sh
```

**Votre propre dépôt.** Chaque matin à 07:30, `morning.sh` commite `memory/`, `config/` et `reports/` et les pousse
sur `origin main` (jamais de code) : `origin` doit donc être un dépôt privé à vous, pas celui reçu. Le clone d'origine
reste en `upstream` (pour récupérer les mises à jour) ; `git remote -v` doit montrer votre dépôt en `origin` :

```
git remote rename origin upstream
gh repo create agent-lab --private --source=. --remote=origin --push
git remote -v
```

`install.sh` crée seulement des fichiers locaux ignorés par git : `config.env` (copié de `config.example.env`, jamais
écrasé : rien à copier à la main), `.claude/` (réglages et skills du manageur), `launchagents/` et `data/`, plus les
gabarits vides de `config/`, `memory/` et `reports/` (ceux-ci, non ignorés, sont à commiter). Il ne charge rien et ne
lance aucun round. Options : `--root`, `--worktrees`, `--projects`, `--brew-bin`, `--prefix`, `--lock`.

Relisez `config.env` : modèles (`MODELE_LAB`, `MODELE_MANAGER`), horaires (`PREMIER_DEPART`, `DERNIER_DEPART`),
`BREW_BIN` (dossier de Homebrew), `TIMEOUT_ROUND`. Puis, depuis `~/agent-lab`, contrôlez sans rien lancer ; avant
toute tâche validée, la réponse attendue est « Round 1 : aucune tâche, rien à faire. » (c'est normal) :

```
scripts/night.sh 1 --check
```

**LaunchAgents.** `install.sh` ne charge rien. Il rend cinq fichiers dans `launchagents/` (`com.agent-lab.night`,
`.morning`, `.morning-retry`, `.manager`, `.now`) et se termine en affichant :

```
Pour en charger un (action de votre part) : cp <fichier> ~/Library/LaunchAgents/ puis launchctl bootstrap gui/$(id -u) <fichier>
```

Chargez d'abord `night` et `morning` (avec `morning-retry` et `now`) :

```
mkdir -p ~/Library/LaunchAgents
for n in night morning morning-retry now; do cp launchagents/com.agent-lab.$n.plist ~/Library/LaunchAgents/ ; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agent-lab.$n.plist ; done
```

Chargez `manager` seulement quand `claude` est connecté et `config.env` relu : il démarre aussitôt (session dans tmux).

```
cp launchagents/com.agent-lab.manager.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agent-lab.manager.plist
launchctl list | grep com.agent-lab
```

Rôles : `night` lance la chaîne de rounds à 23:00 ; `morning` remet les tâches à zéro et sauvegarde la mémoire à 07:30 ;
`morning-retry` réessaie à 09:05, 10:05 et 11:05 ; `manager` garde la session du manageur ouverte (Remote Control, dans
tmux) ; `now` sert aux rounds immédiats. Pour décharger un job : `launchctl bootout gui/$(id -u)/com.agent-lab.night`.

## 4. Le premier matin

1. Ouvrez le manageur : dans un terminal, `cd ~/agent-lab` puis `claude`. CLAUDE.md et les skills de `.claude/` lui
   donnent son rôle. (Avec le LaunchAgent `manager`, la session est déjà ouverte dans tmux : `tmux attach -t manager`.)
2. Dites : « Ajoute le projet `<compte>/<dépôt>` » (skill `add-project`). Il vérifie l'accès avec `gh`, clone le dépôt
   dans `data/projects/`, installe les garde-fous, écrit la fiche `config/projects/<nom>.md` et `.env`, et crée les pages
   de mémoire du projet.
3. Dites : « Prépare la nuit » (skill `plan-night`). Il propose des tâches (un agent, un objectif, un critère de fin
   vérifiable), vous les validez, puis il les écrit dans `config/TASKS.md` et lance `scripts/night.sh 1 --check`.
4. Le lendemain : « Fais la revue du matin » (skill `morning-review`). Relisez les PR sur GitHub et fusionnez-les vous-même.

Autres demandes : « Lance un round maintenant » (`run-now`, même quota qu'un round de nuit), « Ouvre une session directe
sur X » (`direct-session`), « Crée un agent qui fait… » (`create-agent`), « Pourquoi la nuit a raté ? » (`night-diagnosis`).
Agents généraux de `agents/` : `chercheur`, `codeur`, `relecteur`, `testeur` (le nom du fichier est le tag d'une tâche).

## 5. Dépannage : les 5 pièges probables

1. **`gh` non connecté.** L'ajout de projet, le push des branches et l'ouverture des PR échouent. Vérifiez
   `gh auth status`, sinon `gh auth login`.
2. **`claude` non connecté, ou clé d'API à la place de l'abonnement.** `manager.sh` retire `ANTHROPIC_API_KEY` et
   `CLAUDE_CODE_OAUTH_TOKEN` de son environnement : la connexion par abonnement, faite une fois avec `claude`, doit
   suffire. Quota épuisé en pleine nuit : la chaîne attend la remise à zéro et reprend le round, ou s'arrête
   (voir `data/logs/` et `reports/`).
3. **LaunchAgents non chargés, ou `config.env` faux.** Sans eux, rien ne part : `launchctl list | grep com.agent-lab`
   doit lister les jobs. « Lancement impossible (job non chargé ?) » vient de `run-now`. Consultez
   `data/logs/launchd-*.log`. Si les outils sont introuvables, corrigez `BREW_BIN` dans `config.env` (le dossier de la
   commande `brew`, que donne `dirname "$(command -v brew)"`) ; `LAB` doit rester le dossier du clone, sinon `night.sh` refuse de tourner.
4. **Nuit sans tâche validée.** Un round dont la section de `config/TASKS.md` est vide affiche « aucune tâche, rien à
   faire » et ne fait rien : c'est normal. Chaque section `## ROUND N` veut `projet:` (nom d'une fiche
   `config/projects/<nom>.env`) et `branche:` (commençant par `claude/`) ; testez avec `scripts/night.sh N --check`.
   Les tâches sont archivées et remises à zéro chaque matin à 07:30 : replanifiez chaque soir.
5. **Mac en veille ou éteint.** launchd lance un job manqué au réveil, mais `night-chain.sh` ne démarre un round que
   dans la fenêtre `PREMIER_DEPART` (23:00) à `DERNIER_DEPART` (04:00) : hors fenêtre, il ne fait rien. Laissez le Mac
   allumé et branché la nuit.

## Aller plus loin

- Garde-fous : un projet par round, branches `claude/*`, PR en brouillon, tests écrits avant le code, aucun secret
  dans le dépôt (`config.env` reste local).
- Tests du lab : `bash tests/lancer-tous-les-tests.sh` (suite complète) ; `bash tests/installation-ami.sh` rejoue
  l'installation ci-dessus à blanc (faux HOME, `launchctl`/`brew`/`gh`/`claude` doublés).
- Publier votre lab sans données personnelles : `bash scripts/export-lab.sh <dossier-vide>`.
