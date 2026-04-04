#!/bin/sh
set -e

# Startzeit in Sekunden festhalten
START_TIME=$(date +%s)

# Status-Variablen für den Bericht initiieren
STATUS_SSH="Fehlgeschlagen ❌"
STATUS_LINK="Ausstehend ⏳"
STATUS_SYNC1="Ausstehend ⏳"
STATUS_SYNC2="Ausstehend ⏳"
PAUSED_CONTAINERS=""

# Backup-Name für den Bericht (aus ENV oder Hostname)
B_NAME="${BACKUP_NAME:-$(hostname)}"

cleanup_and_report() {
  # 1. Container IMMER aufwecken (falls pausiert)
  if [ -n "$PAUSED_CONTAINERS" ]; then
    echo ""
    echo "⚠️ Wecke Container wieder auf ($PAUSED_CONTAINERS)..."
    docker unpause $PAUSED_CONTAINERS >/dev/null 2>&1 || true
  fi

  # 2. Endzeit und Dauer berechnen
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINS=$((DURATION / 60))
  SECS=$((DURATION % 60))
  FINISH_DATE=$(date "+%Y-%m-%d %H:%M:%S")

  # 3. Bericht generieren
  REPORT="Backup-Bericht: $B_NAME
----------------------------------
[1] SSH-Check: $STATUS_SSH
[2] Hardlinks: $STATUS_LINK
[3] Sync 1:    $STATUS_SYNC1
[4] Sync 2:    $STATUS_SYNC2
----------------------------------
Dauer: $MINS Min, $SECS Sek
Stand: $FINISH_DATE"

  # Konsole-Ausgabe (für Docker Logs)
  echo ""
  echo "================================================="
  echo "📊 BACKUP ZUSAMMENFASSUNG"
  echo "================================================="
  echo "$REPORT"
  echo "================================================="

  # 4. ntfy Benachrichtigung (Optional)
  if [ -n "$NOTIFY_TOPIC" ]; then
    echo "Sende ntfy Nachricht..."
    
    EMOJI="✅"
    if echo "$REPORT" | grep -q "Fehlgeschlagen"; then EMOJI="❌"; fi

    # Ziel-URL zusammenbauen (Default ntfy.sh)
    TARGET_URL="${NOTIFY_URL:-https://ntfy.sh}/$NOTIFY_TOPIC"

    # Senden mit optionaler Authentifizierung
    if [ -n "$NOTIFY_USERNAME" ] && [ -n "$NOTIFY_PASSWORD" ]; then
      curl -s -u "$NOTIFY_USERNAME:$NOTIFY_PASSWORD" \
        -H "Title: Backup $B_NAME" \
        -H "Tags: floppy_disk,$EMOJI" \
        -d "$REPORT" "$TARGET_URL" > /dev/null || echo "ntfy Sendefehler"
    else
      curl -s \
        -H "Title: Backup $B_NAME" \
        -H "Tags: floppy_disk,$EMOJI" \
        -d "$REPORT" "$TARGET_URL" > /dev/null || echo "ntfy Sendefehler"
    fi
  fi
}

# 'trap' fängt das Skript beim Beenden ab
trap cleanup_and_report EXIT

echo "--- Backup gestartet: $(date) ---"

# Validierung
if [ -z "$REMOTE_IP" ]; then
  echo "ERROR: REMOTE_IP nicht gesetzt!"
  exit 1
fi

echo "[1/4] Prüfe SSH-Verbindung..."
if ! sshpass -p "$REMOTE_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" "exit" 2>/dev/null; then
  echo "ERROR: Backup-Server nicht erreichbar."
  exit 1
fi
STATUS_SSH="Erfolgreich ✅"

echo "[2/4] Erstelle Backup-Kopie (Hardlinks)..."
if [ "$INCREMENTAL" = "true" ]; then
  sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" \
    "sudo rm -rf ${REMOTE_PATH}_old; if [ -d $REMOTE_PATH ]; then sudo cp -al $REMOTE_PATH ${REMOTE_PATH}_old; fi"
  STATUS_LINK="Erfolgreich ✅"
else
  STATUS_LINK="Übersprungen ⏭️"
fi

echo "[3/4] Starte ersten Sync (Live)..."
set +e
sshpass -p "$REMOTE_PASS" rsync -avz --delete --rsync-path="sudo rsync" -e "ssh -o StrictHostKeyChecking=accept-new" /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC1_ERR=$?
set -e
if [ $SYNC1_ERR -eq 0 ] || [ $SYNC1_ERR -eq 24 ]; then STATUS_SYNC1="Erfolgreich ✅"; else exit 1; fi

echo "[4/4] Finaler Sync (Pause)..."
TARGETS=$(docker ps --format "{{.Names}}" | grep -viE "docker-volumes-backupper|backup_manager|portainer" | xargs || true)
if [ -n "$TARGETS" ]; then 
    docker pause $TARGETS
    PAUSED_CONTAINERS="$TARGETS"
fi

set +e
sshpass -p "$REMOTE_PASS" rsync -avz --delete --rsync-path="sudo rsync" -e "ssh -o StrictHostKeyChecking=accept-new" /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC2_ERR=$?
set -e
if [ $SYNC2_ERR -eq 0 ] || [ $SYNC2_ERR -eq 24 ]; then STATUS_SYNC2="Erfolgreich ✅"; else exit 1; fi