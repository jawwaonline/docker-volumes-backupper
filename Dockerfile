FROM alpine:3.20

RUN apk add --no-cache \
    rsync \
    openssh-client \
    sshpass \
    docker-cli \
    tzdata \
    dos2unix

COPY backup-run.sh /usr/local/bin/backup-run.sh

# Wir schreiben den Entrypoint frisch im Linux-Format in das Image
RUN echo '#!/bin/sh' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo 'echo "Starte Backup-Container..."' >> /entrypoint.sh && \
    echo 'CRON_SCHEDULE="${CRON_SCHEDULE:-0 3 * * *}"' >> /entrypoint.sh && \
    echo 'cat <<EOF > /etc/crontabs/root' >> /entrypoint.sh && \
    echo 'REMOTE_IP=$REMOTE_IP' >> /entrypoint.sh && \
    echo 'REMOTE_USER=$REMOTE_USER' >> /entrypoint.sh && \
    echo 'REMOTE_PASS=$REMOTE_PASS' >> /entrypoint.sh && \
    echo 'REMOTE_PATH=$REMOTE_PATH' >> /entrypoint.sh && \
    echo 'INCREMENTAL=$INCREMENTAL' >> /entrypoint.sh && \
    echo '$CRON_SCHEDULE /usr/local/bin/backup-run.sh >> /var/log/backup.log 2>&1' >> /entrypoint.sh && \
    echo 'EOF' >> /entrypoint.sh && \
    echo 'echo "Cron gesetzt auf: $CRON_SCHEDULE"' >> /entrypoint.sh && \
    echo 'crond -f -l 2' >> /entrypoint.sh

# Rechte vergeben und backup-run konvertieren (killt Mac-Zeilenumbrüche)
RUN dos2unix /usr/local/bin/backup-run.sh && \
    chmod +x /usr/local/bin/backup-run.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]