#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rsync-backup"
SRC_FILE="$CONFIG_DIR/last-source"
DEST_FILE="$CONFIG_DIR/last-destination"

# Defaults for the first run; previous paths are used on later runs.
LAST_SRC="/LAST/KNOWN/SRC"
LAST_DEST="/LAST/KNOWN/DEST"

if [[ -f "$SRC_FILE" ]]; then
    IFS= read -r LAST_SRC < "$SRC_FILE" || true
fi
if [[ -f "$DEST_FILE" ]]; then
    IFS= read -r LAST_DEST < "$DEST_FILE" || true
fi

prompt_path() {
    local label="$1"
    local default="$2"
    local answer

    read -e -i "$default" -p "$label: " answer
    answer="${answer:-$default}"
    printf -v "$3" '%s' "$answer"
}

prompt_path "Source directory to back up" "$LAST_SRC" SRC
prompt_path "Destination directory for the backup" "$LAST_DEST" DEST

if [[ ! -d "$SRC" ]]; then
    echo "Source directory not found: $SRC" >&2
    exit 1
fi

SRC="$(realpath -e -- "$SRC")"
DEST="$(realpath -m -- "$DEST")"

if [[ "$DEST" == "/" ]]; then
    echo "The root directory / cannot be used as the backup destination." >&2
    exit 1
fi

# Check that the destination is on a mounted drive.
PARENT="$DEST"
while [[ ! -d "$PARENT" ]]; do
    PARENT="$(dirname "$PARENT")"
done
TARGET_MOUNT="$(findmnt -rn -o TARGET -T "$PARENT")"

if [[ "$TARGET_MOUNT" == "/" ]]; then
    echo "The destination appears to be on the system drive; aborting." >&2
    exit 1
fi

# Prevent the source and destination from overlapping.
if [[ "$DEST" == "$SRC" || "$DEST" == "$SRC/"* || "$SRC" == "$DEST/"* ]]; then
    echo "The source and destination must not be the same directory or overlap." >&2
    exit 1
fi

mkdir -p -- "$DEST"

# Remember the paths for the next run.
mkdir -p -- "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
printf '%s\n' "$SRC" > "$SRC_FILE"
printf '%s\n' "$DEST" > "$DEST_FILE"
chmod 600 "$SRC_FILE" "$DEST_FILE"

# By default, perform a dry run only.
DRY_RUN=(--dry-run)
if [[ "${1:-}" == "--run" ]]; then
    echo
    echo "WARNING: --delete removes destination files that no longer exist in the source."
    read -r -p "Run the synchronization? Type YES to confirm: " CONFIRM
    if [[ "$CONFIRM" != "YES" ]]; then
        echo "Aborted."
        exit 0
    fi
    DRY_RUN=()
fi

LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

rsync -a --delete --human-readable --itemize-changes \
    --out-format='%i|%n' \
    "${DRY_RUN[@]}" \
    -- "$SRC/" "$DEST/" > "$LOG"

echo
if [[ -s "$LOG" ]]; then
    mapfile -t CHANGES < "$LOG"
    echo "Affected entries: ${#CHANGES[@]}"
    echo "Action code and filename:"
    for entry in "${CHANGES[@]}"; do
        printf '  %s  %s\n' "${entry%%|*}" "${entry#*|}"
    done
else
    echo "No changes required."
fi

if [[ "${1:-}" != "--run" ]]; then
    echo
    echo "This was a dry run. To perform the synchronization, run: $0 --run"
fi
