FROM alpine:3.20

# Benötigte Pakete installieren
RUN apk add --no-cache \
    rsync \
    openssh-client \
    sshpass \
    docker-cli \
    tzdata \
    curl \
    dos2unix

# Skripte kopieren
COPY backup-run.sh /usr/local/bin/backup-run.sh
COPY entrypoint.sh /entrypoint.sh

# Windows-Zeilenumbrüche entfernen & Ausführbar machen
RUN dos2unix /usr/local/bin/backup-run.sh /entrypoint.sh && \
    chmod +x /usr/local/bin/backup-run.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]