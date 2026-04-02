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

# === NEU: Die Notfall-Rettungs-Funktion (Wird IMMER am Ende aufgerufen) ===
cleanup_and_report() {
  # 1. Container IMMER aufwecken, egal was passiert ist!
  if [ -n "$PAUSED_CONTAINERS" ]; then
    echo ""
    echo "⚠️ Wecke Container wieder auf ($PAUSED_CONTAINERS)..."
    docker unpause $PAUSED_CONTAINERS >/dev/null 2>&1 || true
  fi

  # 2. Endzeit berechnen
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINS=$((DURATION / 60))
  SECS=$((DURATION % 60))

  # 3. Bericht drucken
  echo ""
  echo "================================================="
  echo "📊 BACKUP ZUSAMMENFASSUNG"
  echo "================================================="
  echo "[1] SSH-Verbindung:       $STATUS_SSH"
  echo "[2] Inkrementelle Kopie:  $STATUS_LINK"
  echo "[3] Erster Sync (Live):   $STATUS_SYNC1"
  echo "[4] Finaler Sync (Pause): $STATUS_SYNC2"
  echo "-------------------------------------------------"
  echo "⏱️ Dauer: $MINS Minuten und $SECS Sekunden"
  echo "🏁 Beendet am: $(date)"
  echo "================================================="
}

# 'trap' fängt das Skript beim Beenden (EXIT) ab und führt cleanup_and_report aus
trap cleanup_and_report EXIT

echo "================================================="
echo "--- Backup gestartet: $(date) ---"
echo "================================================="

if [ -z "$REMOTE_IP" ]; then
  echo "ERROR: REMOTE_IP nicht gesetzt!"
  exit 1
fi

echo "[1/4] Prüfe SSH-Verbindung (Timeout: 10s)..."
if ! sshpass -p "$REMOTE_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" "exit" 2>/dev/null; then
  echo "ERROR: Backup-Server ($REMOTE_IP) ist nicht erreichbar oder Login fehlerhaft!"
  exit 1
fi
STATUS_SSH="Erfolgreich ✅"

echo "[2/4] Erstelle Backup-Kopie auf dem Ziel..."
STATUS_LINK="Fehlgeschlagen ❌"
INCREMENTAL="${INCREMENTAL:-true}"
if [ "$INCREMENTAL" = "true" ]; then
  echo "      -> Inkrementelles Backup (Hardlinks) aktiv."
  sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" \
    "sudo rm -rf ${REMOTE_PATH}_old; if [ -d $REMOTE_PATH ]; then sudo cp -al $REMOTE_PATH ${REMOTE_PATH}_old; fi"
  STATUS_LINK="Erfolgreich ✅"
else
  echo "      -> Übersprungen (INCREMENTAL=false)."
  STATUS_LINK="Übersprungen ⏭️"
fi

echo "[3/4] Starte ersten großen Sync (während Container laufen)..."
STATUS_SYNC1="Fehlgeschlagen ❌"
set +e
sshpass -p "$REMOTE_PASS" rsync -avz --stats --delete --rsync-path="sudo rsync" -e "ssh -o StrictHostKeyChecking=accept-new" \
  /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC1_ERROR=$?
set -e

if [ $SYNC1_ERROR -eq 0 ]; then
  STATUS_SYNC1="Erfolgreich ✅"
elif [ $SYNC1_ERROR -eq 24 ]; then
  STATUS_SYNC1="Erfolgreich ✅ (Code 24: Dateien verändert)"
else
  STATUS_SYNC1="Fehlgeschlagen ❌ (Code: $SYNC1_ERROR)"
  echo "ERROR: Kritischer Fehler beim ersten Sync. Breche ab."
  exit $SYNC1_ERROR
fi

echo "[4/4] Pausiere Container für finalen, fehlerfreien Sync..."
STATUS_SYNC2="Fehlgeschlagen ❌"

# FIX: Schließt das Skript selbst (egal ob es backup_manager oder docker-volumes-backupper heißt) UND portainer aus!
TARGETS=$(docker ps --format "{{.Names}}" | grep -viE "docker-volumes-backupper|backup_manager|portainer" | xargs || true)

if [ -n "$TARGETS" ]; then
  docker pause $TARGETS
  PAUSED_CONTAINERS="$TARGETS" # Speichert die Liste für die Trap-Funktion ganz oben!
fi

set +e
sshpass -p "$REMOTE_PASS" rsync -avz --delete --rsync-path="sudo rsync" -e "ssh -o StrictHostKeyChecking=accept-new" \
  /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC_ERROR=$?
set -e

if [ $SYNC_ERROR -eq 0 ]; then
  STATUS_SYNC2="Erfolgreich ✅"
elif [ $SYNC_ERROR -eq 24 ]; then
  STATUS_SYNC2="Erfolgreich ✅ (Code 24)"
else
  STATUS_SYNC2="Fehlgeschlagen ❌ (Code: $SYNC_ERROR)"
  echo "ERROR: Finaler Sync komplett fehlgeschlagen!"
  exit $SYNC_ERROR
fi