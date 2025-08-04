#!/bin/bash

CONTAINER_NAME="minecraftlazymc-mc-1"
BACKUP_DIR="/home/config/PaperMC"
DEST_DIR="/home/config/PaperMC/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Check if the container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
  echo "Minecraft container not found. Skipping backup."
  exit 0
fi

# Is the container running?
IS_RUNNING=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")

if [ "$IS_RUNNING" = "true" ]; then
  echo "Minecraft container is running."

  # Check if players are online
  PLAYER_LIST=$(docker exec "$CONTAINER_NAME" rcon-cli list)
  PLAYER_COUNT=$(echo "$PLAYER_LIST" | grep -oP 'There are \K[0-9]+')

  if [ "$PLAYER_COUNT" -eq 0 ]; then
    echo "No players are online. Skipping backup."
    exit 0
  else
    echo "Players are online ($PLAYER_COUNT). Proceeding with backup."
  fi

  # Notify players and save
  docker exec "$CONTAINER_NAME" rcon-cli say "⚠️ Server backup starting. Expect a quick lag spike..."
  docker exec "$CONTAINER_NAME" rcon-cli save-off
  sleep 3
  docker exec "$CONTAINER_NAME" rcon-cli save-all
  sleep 3

elif [ "$IS_RUNNING" = "false" ]; then
  # Container is not running, check how recently it stopped
  FINISHED_AT=$(docker inspect -f '{{.State.FinishedAt}}' "$CONTAINER_NAME")
  FINISHED_AT_UNIX=$(date -d "$FINISHED_AT" +%s)
  NOW_UNIX=$(date +%s)
  DIFF=$((NOW_UNIX - FINISHED_AT_UNIX))

  if [ "$DIFF" -gt 600 ]; then
    echo "Minecraft container has not been running in the last 10 minutes. Skipping backup."
    exit 0
  else
    echo "Minecraft container stopped within the last 10 minutes. Proceeding with backup (player check skipped)."
  fi
else
  echo "Error: Unable to determine container state."
  exit 1
fi

# Create backup directory
mkdir -p "$DEST_DIR"

# Create and compress the backup
echo "Creating backup archive..."
tar -cvf "$DEST_DIR/backup_$TIMESTAMP.tar" -C "$BACKUP_DIR" Rose2 Rose2_nether Rose2_the_end
gzip -6 "$DEST_DIR/backup_$TIMESTAMP.tar"
echo "Backup complete: backup_$TIMESTAMP.tar.gz"

# Re-enable saving and notify players if the server is still running
if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME")" = "true" ]; then
  docker exec "$CONTAINER_NAME" rcon-cli save-on
  docker exec "$CONTAINER_NAME" rcon-cli say "✅ Backup complete! Thank you for your patience."
fi

# Rotate old backups (keep only the latest 10)
cd "$DEST_DIR" || exit
ls -t | grep 'backup_.*\.tar\.gz' | sed -e '1,10d' | xargs -d '\n' rm -f

echo "Backup script finished successfully."
