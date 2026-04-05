#!/bin/sh
set -e

START_TIME=$(date +%s)

STATUS_SSH="Fehlgeschlagen ❌"
STATUS_LINK="Ausstehend ⏳"
STATUS_SYNC1="Ausstehend ⏳"
STATUS_SYNC2="Ausstehend ⏳"
PAUSED_CONTAINERS=""

B_NAME="${BACKUP_NAME:-$(hostname)}"

# ----------------------------
# ntfy Sender
# ----------------------------
send_ntfy() {
  TITLE="$1"
  MESSAGE="$2"
  TAGS="$3"

  if [ -z "$NOTIFY_URL" ]; then return; fi

  TARGET_URL=$(echo "$NOTIFY_URL" | sed 's/\/$//')

  if [ -n "$NOTIFY_USERNAME" ] && [ -n "$NOTIFY_PASSWORD" ]; then
    curl -sS -o /dev/null --connect-timeout 5 --max-time 20 \
      -u "$NOTIFY_USERNAME:$NOTIFY_PASSWORD" \
      -H "Title: $TITLE" \
      -H "Tags: $TAGS" \
      -H "Content-Type: text/plain" \
      -d "$MESSAGE" \
      "$TARGET_URL" || echo "⚠️ ntfy Fehler"
  else
    curl -sS -o /dev/null --connect-timeout 5 --max-time 20 \
      -H "Title: $TITLE" \
      -H "Tags: $TAGS" \
      -H "Content-Type: text/plain" \
      -d "$MESSAGE" \
      "$TARGET_URL" || echo "⚠️ ntfy Fehler"
  fi
}

# ----------------------------
# Cleanup & Report
# ----------------------------
cleanup_and_report() {
  echo ""
  echo "📊 Cleanup & Bericht..."

  if [ -n "$PAUSED_CONTAINERS" ]; then
    echo "▶️ Unpause Container..."
    docker unpause $PAUSED_CONTAINERS >/dev/null 2>&1 || true
  fi

  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  MINS=$((DURATION / 60))
  SECS=$((DURATION % 60))
  FINISH_DATE=$(date "+%Y-%m-%d %H:%M:%S")

  REPORT="[1] SSH: $STATUS_SSH
[2] Hardlinks: $STATUS_LINK
[3] Sync1: $STATUS_SYNC1
[4] Sync2: $STATUS_SYNC2
-----------------------------
Dauer: ${MINS}m ${SECS}s
Zeit: $FINISH_DATE"

  echo "======================================"
  echo "📊 BACKUP REPORT"
  echo "======================================"
  echo "$REPORT"
  echo "======================================"

  EMOJI="✅"
  echo "$REPORT" | grep -q "Fehlgeschlagen" && EMOJI="❌"
  send_ntfy "Backup Ergebnis: $B_NAME" "$REPORT" "floppy_disk,$EMOJI"
}

trap cleanup_and_report EXIT

# ----------------------------
# Backup starten
# ----------------------------
echo "🚀 Backup gestartet: $(date)"
send_ntfy "Backup gestartet: $B_NAME" "Backup gestartet um $(date '+%H:%M:%S')" "hourglass"

if [ -z "$REMOTE_IP" ]; then
  echo "❌ REMOTE_IP fehlt!"
  exit 1
fi

# ----------------------------
# 1/4 SSH Check
# ----------------------------
echo "[1/4] SSH Verbindung prüfen..."
if sshpass -p "$REMOTE_PASS" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" "exit" 2>/dev/null; then
  STATUS_SSH="OK ✅"
else
  STATUS_SSH="Fehlgeschlagen ❌"
  exit 1
fi

# ----------------------------
# 2/4 Hardlinks
# ----------------------------
echo "[2/4] Hardlink Backup..."
if [ "$INCREMENTAL" = "true" ]; then
  STATUS_LINK="Fehlgeschlagen ❌"
  # Nutze sudo für rm und cp auf dem Ziel
  sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=accept-new "$REMOTE_USER@$REMOTE_IP" \
    "sudo rm -rf ${REMOTE_PATH}_old; if [ -d $REMOTE_PATH ]; then sudo cp -al $REMOTE_PATH ${REMOTE_PATH}_old; fi"
  STATUS_LINK="OK ✅"
else
  STATUS_LINK="Übersprungen ⏭️"
fi

# ----------------------------
# 3/4 Sync (Die Lösung für dein Problem ist --rsync-path="sudo rsync")
# ----------------------------
echo "[3/4] Erster Sync..."
STATUS_SYNC1="Fehlgeschlagen ❌"
set +e
sshpass -p "$REMOTE_PASS" rsync -avz --delete \
  --rsync-path="sudo rsync" \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC1_ERR=$?
set -e

if [ $SYNC1_ERR -eq 0 ] || [ $SYNC1_ERR -eq 24 ]; then
  STATUS_SYNC1="OK ✅"
else
  echo "❌ Sync1 Fehler ($SYNC1_ERR)"
  exit 1
fi

# ----------------------------
# 4/4 Final Sync
# ----------------------------
echo "[4/4] Final Sync..."
STATUS_SYNC2="Fehlgeschlagen ❌"

TARGETS=$(docker ps --format "{{.Names}}" | grep -viE "docker-volumes-backupper|backup_manager|portainer" | xargs || true)

if [ -n "$TARGETS" ]; then
  docker pause $TARGETS
  PAUSED_CONTAINERS="$TARGETS"
fi

set +e
sshpass -p "$REMOTE_PASS" rsync -avz --delete \
  --rsync-path="sudo rsync" \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  /source_data/ "$REMOTE_USER@$REMOTE_IP:$REMOTE_PATH/"
SYNC2_ERR=$?
set -e

if [ $SYNC2_ERR -eq 0 ] || [ $SYNC2_ERR -eq 24 ]; then
  STATUS_SYNC2="OK ✅"
else
  echo "❌ Sync2 Fehler ($SYNC2_ERR)"
  exit 1
fi

echo "✅ Backup erfolgreich abgeschlossen"