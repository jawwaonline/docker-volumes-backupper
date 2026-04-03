#!/bin/sh

set -e

echo "Starte Backup-Container..."

# Default Cron
CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"

# ENV in crontab schreiben
cat <<EOF > /etc/crontabs/root
REMOTE_IP=$REMOTE_IP
REMOTE_USER=$REMOTE_USER
REMOTE_PASS=$REMOTE_PASS
REMOTE_PATH=$REMOTE_PATH
$CRON_SCHEDULE /usr/local/bin/backup-run.sh >> /var/log/backup.log 2>&1
EOF

echo "Cron gesetzt auf: $CRON_SCHEDULE"

crond -f -l 2