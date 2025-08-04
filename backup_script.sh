#!/bin/bash

CONTAINER_NAME="minecraftlazymc-mc-1"
BACKUP_DIR="/home/config/PaperMC"
DEST_DIR="/home/config/PaperMC/backups"
LOG_FILE="$DEST_DIR/backup.log"

# Ensure backup destination exists
mkdir -p "$DEST_DIR"

# Truncate log if larger than 100MB
if [ -f "$LOG_FILE" ] && [ "$(stat -c %s "$LOG_FILE")" -gt $((100 * 1024 * 1024)) ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - Log file exceeded 100MB. Truncating..." > "$LOG_FILE"
fi

# Log everything from this point onward
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Backup started at $(date '+%Y-%m-%d %H:%M:%S') ==="

# Check if the container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
  echo "Container '$CONTAINER_NAME' not found. Skipping backup."
  exit 0
fi

# Determine if the container is running
IS_RUNNING=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")

if [ "$IS_RUNNING" == "true" ]; then
  echo "Container is running. Checking player activity..."

  # Get player list via RCON
  PLAYER_LIST=$(docker exec "$CONTAINER_NAME" rcon-cli list 2>/dev/null)

  if [[ "$PLAYER_LIST" =~ There\ are\ 0\ of\ a\ max\ [0-9]+\ players\ online ]]; then
    echo "No players online. Skipping backup."
    exit 0
  else
    echo "Players online. Proceeding with backup."
    docker exec "$CONTAINER_NAME" rcon-cli say ⚠️ Server backup starting. Expect a quick lag spike...
    docker exec "$CONTAINER_NAME" rcon-cli save-off
    sleep 3
    docker exec "$CONTAINER_NAME" rcon-cli save-all
    sleep 3
  fi
else
  # If the container is not running, check last stop time
  FINISHED_AT=$(docker inspect -f '{{.State.FinishedAt}}' "$CONTAINER_NAME")
  FINISHED_AT_UNIX=$(date -d "$FINISHED_AT" +%s)
  NOW_UNIX=$(date +%s)
  DIFF=$((NOW_UNIX - FINISHED_AT_UNIX))

  if [ "$DIFF" -gt 600 ]; then
    echo "Container has not been running in the last 10 minutes. Skipping backup."
    exit 0
  else
    echo "Container stopped within the last 10 minutes. Proceeding with backup."
  fi
fi

# Perform the backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ARCHIVE_NAME="backup_$TIMESTAMP.tar"
echo "Creating backup archive $ARCHIVE_NAME..."

tar -cvf "$DEST_DIR/$ARCHIVE_NAME" -C "$BACKUP_DIR" Rose2 Rose2_nether Rose2_the_end
gzip -6 "$DEST_DIR/$ARCHIVE_NAME"
echo "Backup archive created: $DEST_DIR/$ARCHIVE_NAME.gz"

# Re-enable saving and notify players if still running
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" == "true" ]; then
  docker exec "$CONTAINER_NAME" rcon-cli save-on
  docker exec "$CONTAINER_NAME" rcon-cli say ✅ Backup complete! Thank you for your patience.
fi

# Prune old backups, keep only latest 10
cd "$DEST_DIR" || exit
echo "Cleaning up old backups..."
ls -t | grep 'backup_.*\.tar\.gz' | sed -e '1,10d' | xargs -r -d '\n' rm -f

echo "Backup completed at $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="
