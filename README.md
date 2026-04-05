# 🐳 Docker Backup Manager

Ein schlanker Docker-Container für automatisierte Backups von Docker-Volumes per `rsync` über SSH.

## ✨ Features

- 🔄 Automatisches Backup via Cron
- 📦 Rsync-basierte Synchronisation (inkrementell + effizient)
- 🗂 Rotation (`_old` Backup via Hardlinks, optional)
- 🛡 Fallback: Bricht sofort ab, wenn Zielserver offline ist (Timeout)
- ⏸ Pausiert Container für konsistente Backups (Portainer & Backup-Skript bleiben aktiv!)
- 🚀 Läuft komplett als Container (kein Host-Skript nötig)

---

## 🚀 Quick Start

```yaml
version: "3.8"

services:
  backup_manager:
    image: ghcr.io/jawwaonline/docker-volumes-backupper:latest
    container_name: docker-volumes-backupper
    restart: unless-stopped

    environment:
      REMOTE_IP: 192.168.168.1
      REMOTE_USER: user
      REMOTE_PASS: pass
      REMOTE_PATH: /home/pi/docker_volumes
      CRON_SCHEDULE: "0 3 * * *"
      INCREMENTAL: "true" # Empfohlen! Erstellt ein Backup vom Backup (siehe unten)

    volumes:
      - /home/docker_volumes:/source_data:ro
      - /var/run/docker.sock:/var/run/docker.sock
```

### ⚙️ Wie funktioniert INCREMENTAL?

Der Parameter INCREMENTAL entscheidet darüber, ob du ein "Sicherheitsnetz" für deine Daten hast:

INCREMENTAL: "true" (Empfohlen)
Bevor der nächtliche Sync startet, erstellt das Skript blitzschnell eine Kopie deines letzten Backups und nennt sie \_old.
Der große Vorteil: Zerschießt du dir aus Versehen eine Datenbank und bemerkst es erst am nächsten Tag, hat das Backup diese kaputte Datenbank zwar synchronisiert, aber du findest im \_old Ordner noch den intakten Stand von gestern! Da hierfür "Hardlinks" genutzt werden, verbraucht diese Kopie 0 Byte zusätzlichen Speicherplatz.

INCREMENTAL: "false"
Die Daten werden direkt und ohne doppelten Boden auf den Zielrechner gespiegelt.
Wann solltest du das nutzen? Nur, wenn deine Zielfestplatte (z.B. am Raspberry Pi) im Windows-Format FAT32 oder exFAT formatiert ist. Diese Formate unterstützen keine Hardlinks, wodurch der Kopiervorgang fehlschlagen würde.

### 🧪 Manuelles Backup testen

```Bash
docker exec -it docker-volumes-backupper /usr/local/bin/backup-run.sh
```

### 🔔 Benachrichtigungen (ntfy)

Optional kannst du Status-Berichte an einen [ntfy](https://ntfy.sh) Server senden.

```yaml
environment:
  NOTIFY_URL: "https://ntfy.sh/mein_topic"
  NOTIFY_USERNAME: "user" # Optional
  NOTIFY_PASSWORD: "pass" # Optional
```
