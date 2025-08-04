#!/bin/bash

CONTAINER_NAME="minecraftlazymc-mc-1"

# Check if the container exists
if ! docker ps -a --format '{{.Names}}' | grep -q "^$CONTAINER_NAME$"; then
  echo "Minecraft container not found. Skipping backup."
  exit 0
fi

# Check if the container is running
if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" | grep -q true; then
  echo "Minecraft container is running. Preparing for backup."

  # Notify players and prepare for backup
  docker exec "$CONTAINER_NAME" rcon-cli say ⚠️ Server backup starting. Expect a quick lag spike...
  docker exec "$CONTAINER_NAME" rcon-cli save-off
  sleep 3
  docker exec "$CONTAINER_NAME" rcon-cli save-all
  sleep 3
else
  # Not running, check if it exited in the last 30 minutes
  FINISHED_AT=$(docker inspect -f '{{.State.FinishedAt}}' "$CONTAINER_NAME")
  FINISHED_AT_UNIX=$(date -d "$FINISHED_AT" +%s)
  NOW_UNIX=$(date +%s)
  DIFF=$((NOW_UNIX - FINISHED_AT_UNIX))

  if [ "$DIFF" -gt 600 ]; then
    echo "Minecraft container has not been running in the last 10 minutes. Skipping backup."
    exit 0
  else
    echo "Minecraft container stopped within the last 10 minutes. Proceeding with backup."
  fi
fi

# Directory containing folders to back up
BACKUP_DIR="/home/config/PaperMC"
DEST_DIR="/home/config/PaperMC/backups"
mkdir -p "$DEST_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Create and compress the backup
tar -cvf "$DEST_DIR/backup_$TIMESTAMP.tar" -C "$BACKUP_DIR" Rose2 Rose2_nether Rose2_the_end
gzip -6 "$DEST_DIR/backup_$TIMESTAMP.tar"

# Re-enable saving and notify players if the container is still running
if docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" | grep -q true; then
  docker exec "$CONTAINER_NAME" rcon-cli save-on
  docker exec "$CONTAINER_NAME" rcon-cli say ✅ Backup complete! Thank you for your patience.
fi

# Keep only the latest 10 backups
cd "$DEST_DIR" || exit
ls -t | grep 'backup_.*\.tar\.gz' | sed -e '1,10d' | xargs -d '\n' rm -f
