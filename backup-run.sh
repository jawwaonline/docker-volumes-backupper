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

cleanup_and_report() {
  # 1. Container IMMER aufwecken
  if [ -n "$PAUSED_CONTAINERS" ]; then
    echo ""
    echo "⚠️ Wecke Container wieder auf ($PAUSED_CONTAINERS)..."
    docker unpause $PAUSED_CONTAINERS >/dev/null 2>&1 || true
  fi

  # 2. Endzeit und Dauer
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINS=$((DURATION / 60))
  SECS=$((DURATION % 60))
  FINISH_DATE=$(date "+%Y-%m-%d %H:%M:%S")

  # 3. Bericht generieren
  REPORT="[1] SSH: $STATUS_SSH
[2] Kopie: $STATUS_LINK
[3] Sync 1: $STATUS_SYNC1
[4] Sync 2: $STATUS_SYNC2
Dauer: $MINS Min, $SECS Sek"

  # Konsole-Ausgabe
  echo ""
  echo "================================================="
  echo "📊 BACKUP ZUSAMMENFASSUNG"
  echo "================================================="
  echo "$REPORT"
  echo "🏁 Beendet am: $FINISH_DATE"
  echo "================================================="

  # 4. ntfy Benachrichtigung (Optional)
  if [ -n "$NOTIFY_TOPIC" ]; then
    echo "Sending ntfy notification..."
    
    # Bestimme Icon basierend auf Erfolg
    EMOJI="✅"
    if echo "$REPORT" | grep -q "Fehlgeschlagen"; then EMOJI="❌"; fi

    # Authentifizierung vorbereiten
    AUTH_HEADER=""
    if [ -n "$NOTIFY_USERNAME" ] && [ -n "$NOTIFY_PASSWORD" ]; then
        AUTH_HEADER="-u $NOTIFY_USERNAME:$NOTIFY_PASSWORD"
    fi

    curl $AUTH_HEADER \
      -H "Title: Backup Report: $(hostname)" \
      -H "Tags: floppy_disk, $EMOJI" \
      -d "$REPORT" \
      "${NOTIFY_URL:-https://ntfy.sh}/$NOTIFY_TOPIC" >/dev/null 2>&1 || echo "ntfy failed"
  fi
}

trap cleanup_and_report EXIT

# ... (Rest des Skripts bleibt identisch zu deiner Vorlage) ...
echo "================================================="
echo "--- Backup gestartet: $(date) ---"
echo "================================================="

if [ -z "$REMOTE_IP" ]; then
  echo "ERROR: REMOTE_IP nicht gesetzt!"
  exit 1
fi

echo "[1/4] Prüfe SSH-Verbindung..."
if ! sshpass -p "$REMOTE_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" "exit" 2>/dev/null; then
  exit 1
fi
STATUS_SSH="Erfolgreich ✅"

echo "[2/4] Erstelle Backup-Kopie..."
STATUS_LINK="Fehlgeschlagen ❌"
if [ "$INCREMENTAL" = "true" ]; then
  sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" \
    "sudo rm -rf ${REMOTE_PATH}_old; if [ -d $REMOTE_PATH ]; then sudo cp -al $REMOTE_PATH ${REMOTE_PATH}_old; fi"
  STATUS_LINK="Erfolgreich ✅"
else
  STATUS_LINK="Übersprungen ⏭️"
fi

echo "[3/4] Starte ersten Sync..."
STATUS_SYNC1="Fehlgeschlagen ❌"
set +e
sshpass -p "$REMOTE_PASS" rsync -avz --delete --rsync-path="sudo rsync" -e "ssh -o StrictHostKeyChecking=accept-new" /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC1_ERROR=$?
set -e
if [ $SYNC1_ERROR -eq 0 ] || [ $SYNC1_ERROR -eq 24 ]; then STATUS_SYNC1="Erfolgreich ✅"; else exit $SYNC1_ERROR; fi

echo "[4/4] Finaler Sync (Pause)..."
STATUS_SYNC2="Fehlgeschlagen ❌"
TARGETS=$(docker ps --format "{{.Names}}" | grep -viE "docker-volumes-backupper|backup_manager|portainer" | xargs || true)
if [ -n "$TARGETS" ]; then docker pause $TARGETS; PAUSED_CONTAINERS="$TARGETS"; fi

set +e
sshpass -p "$REMOTE_PASS" rsync -avz --delete --rsync-path="sudo rsync" -e "ssh -o StrictHostKeyChecking=accept-new" /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC_ERROR=$?
set -e
if [ $SYNC_ERROR -eq 0 ] || [ $SYNC_ERROR -eq 24 ]; then STATUS_SYNC2="Erfolgreich ✅"; else exit $SYNC_ERROR; fi