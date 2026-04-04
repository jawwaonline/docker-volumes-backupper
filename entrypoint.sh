#!/bin/sh
set -e

echo "Initialisiere Backup-Container..."

# 1. Alle Docker-Umgebungsvariablen in Datei sichern
# Dies ist nötig, da Cron eine leere Shell ohne ENVs startet.
printenv | grep -v "no_proxy" > /etc/environment

# 2. Cron Schedule festlegen
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"

# 3. Crontab erstellen
# Wir laden die /etc/environment BEVOR das Skript startet.
echo "$CRON_SCHEDULE . /etc/environment; /usr/local/bin/backup-run.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

echo "Cron-Job registriert: $CRON_SCHEDULE"

# 4. Cron-Daemon im Vordergrund starten
crond -f -l 2