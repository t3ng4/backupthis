#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rsync-backup"
SRC_FILE="$CONFIG_DIR/letzte-quelle"
DEST_FILE="$CONFIG_DIR/letztes-ziel"

# Vorgaben beim ersten Start; danach werden die letzten Pfade verwendet.
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

prompt_path "Quelle (Ordner, der gesichert wird)" "$LAST_SRC" SRC
prompt_path "Ziel (Ordner für die Sicherung)" "$LAST_DEST" DEST

if [[ ! -d "$SRC" ]]; then
    echo "Quellordner nicht gefunden: $SRC" >&2
    exit 1
fi

SRC="$(realpath -e -- "$SRC")"
DEST="$(realpath -m -- "$DEST")"

if [[ "$DEST" == "/" ]]; then
    echo "Das Wurzelverzeichnis / kann nicht als Sicherungsziel verwendet werden." >&2
    exit 1
fi

# Prüfen, ob das Ziel auf einem eingehängten Laufwerk liegt.
PARENT="$DEST"
while [[ ! -d "$PARENT" ]]; do
    PARENT="$(dirname "$PARENT")"
done
TARGET_MOUNT="$(findmnt -rn -o TARGET -T "$PARENT")"

if [[ "$TARGET_MOUNT" == "/" ]]; then
    echo "Das Ziel liegt offenbar auf dem Systemlaufwerk; Sicherung abgebrochen." >&2
    exit 1
fi

# Quelle und Ziel dürfen sich nicht überschneiden.
if [[ "$DEST" == "$SRC" || "$DEST" == "$SRC/"* || "$SRC" == "$DEST/"* ]]; then
    echo "Quelle und Ziel dürfen nicht identisch sein oder ineinander liegen." >&2
    exit 1
fi

mkdir -p -- "$DEST"

# Pfade für den nächsten Start merken.
mkdir -p -- "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"
printf '%s\n' "$SRC" > "$SRC_FILE"
printf '%s\n' "$DEST" > "$DEST_FILE"
chmod 600 "$SRC_FILE" "$DEST_FILE"

# Standardmäßig nur ein Testlauf.
DRY_RUN=(--dry-run)
if [[ "${1:-}" == "--run" ]]; then
    echo
    echo "ACHTUNG: --delete löscht im Ziel Dateien, die in der Quelle nicht mehr existieren."
    read -r -p "Wirklich synchronisieren? Zum Bestätigen JA eingeben: " CONFIRM
    if [[ "$CONFIRM" != "JA" ]]; then
        echo "Abgebrochen."
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
    echo "Betroffene Einträge: ${#CHANGES[@]}"
    echo "Aktionscode und Dateiname:"
    for entry in "${CHANGES[@]}"; do
        printf '  %s  %s\n' "${entry%%|*}" "${entry#*|}"
    done
else
    echo "Keine Änderungen nötig."
fi

if [[ "${1:-}" != "--run" ]]; then
    echo
    echo "Das war ein Testlauf. Zum tatsächlichen Synchronisieren: $0 --run"
fi
