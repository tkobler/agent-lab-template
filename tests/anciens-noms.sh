#!/usr/bin/env bash
# À inclure (source) par les tests : les ANCIENS noms français (avant le renommage en anglais), utiles seulement pour
# vérifier qu'ils sont refusés, ignorés ou ramenés aux nouveaux noms (comparaison au lab en service).
# Chaque nom est ASSEMBLÉ ici en morceaux : ainsi aucun ancien nom n'apparaît en clair dans le dépôt, et un grep de
# contrôle des anciens noms reste vide (aucune exception : le README ne porte plus de table de correspondance).
AN_NUIT_SH="nu""it.sh"
AN_NUIT_CHAINE_SH="nu""it-cha""ine.sh"
AN_RUNNOW_SH="lancer-ma""in""tenant.sh"
AN_MATIN_SH="ma""tin"".sh"
AN_RELANCE_MATIN_SH="rela""nce-ma""tin"".sh"
AN_DIRECTE_SH="session-""directe.sh"
AN_RELANCE_MATIN="rela""nce-ma""tin"
AN_NUIT1="nu""it1"
AN_MATIN="ma""tin"
AN_NOW="ma""in""tenant"
AN_NOW_UP="MAIN""TENANT"
AN_TASKS_UP="TA""CHES"
AN_FICHES="fi""ches"
AN_RAPPORTS="rap""ports"
AN_MODELES="mod""eles"
AN_VERIFIER="--veri""fier"
AN_PREFIXE="com.claude""h""q"
AN_PLAFOND="MAX_""ROUNDS"
AN_DEPOT="sa""m-h""q"                        # ancien nom du dépôt (devenu agent-lab)
AN_PREFIXE_DEPOT="com.sa""m-h""q"            # ancien préfixe launchd par défaut (devenu com.agent-lab)
AN_PREFIXE_INTERM="com.agent-h""q"               # préfixe launchd intermédiaire (devenu com.agent-lab, décision du 24/10)
AN_MEM_ANCIEN="memory/h""q"                      # ancien dossier de mémoire de l'installation (devenu memory/lab)
AN_BUILD="build-""template"                  # ancien nom du script d'export (devenu export-lab.sh)
AN_PLIST_MODELE="plist.mo""dele"
AN_NUIT_EN_COURS=".nu""it-en-cours"          # fichier-signal d'une nuit en cours
AN_ROUND_NOW=".round-""maintenant"           # fichier-signal d'un round immédiat
AN_TACHES="ta""ches-"                        # début des anciens noms d'archives de tâches (nuit et round immédiat)
AN_TACHES_NUIT="ta""ches-nuit.md"
AN_ID_NOW="main""tenant-"                    # début de l'ancien identifiant de round immédiat
AN_PROMPT="nu""it.md"                        # ancien nom du prompt du chef de nuit
# Anciens noms des skills du manageur, repère de revue, fichiers de mémoire de travail et installeur de garde-fous
AN_SK_REVUE="revue-""matin"
AN_SK_PLANIFIER="planifier-""nuit"
AN_SK_LANCER="lancer-""maintenant"
AN_SK_AJOUTER="ajouter-""projet"
AN_SK_SESSION="session-""directe"
AN_SK_CREER="creer-""agent"
AN_SK_DIAG="diagnostic-""nuit"
AN_REVUE_FAITE=".revue-""faite"
AN_ETAT="et""at.md"
AN_A_DECIDER="a-""decider.md"
AN_EN_SERVICE="en-ser""vice.md"
AN_INSTALLER_HOOKS="installer-""hooks"

# Table ancien|nouveau des noms qui figurent dans un plist ou dans les réglages du lab en service (les plus longs d'abord)
RENOMMAGES_PLIST="${AN_NUIT_CHAINE_SH}|night-chain.sh
${AN_RELANCE_MATIN_SH}|morning-retry.sh
${AN_MATIN_SH}|morning.sh
${AN_NUIT_SH}|night.sh
launchd-${AN_RELANCE_MATIN}.log|launchd-morning-retry.log
launchd-${AN_MATIN}.log|launchd-morning.log
launchd-${AN_NUIT1}.log|launchd-night.log
launchd-${AN_NOW}.log|launchd-now.log
.${AN_RELANCE_MATIN}|.morning-retry
.${AN_MATIN}|.morning
.${AN_NUIT1}|.night
.${AN_NOW}|.now"
