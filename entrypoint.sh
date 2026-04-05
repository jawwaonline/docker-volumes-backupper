#!/bin/sh
set -e

echo "🔧 Initialisiere Container..."

# ENV sauber speichern (wichtig!)
printenv > /env.sh

CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"

echo "$CRON_SCHEDULE . /env.sh; /usr/local/bin/backup-run.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root

echo "🕒 Cron: $CRON_SCHEDULE"

crond -f -l 2