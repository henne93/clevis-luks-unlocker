#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/clevis-luks-unlocker.conf"

if [ ! -f "$CONFIG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') ERROR: Config file not found: $CONFIG" >&2
    exit 1
fi

# shellcheck source=clevis-luks-unlocker.conf
. "$CONFIG"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"
}

wait_for_tang() {
    local start=$SECONDS

    while [ $((SECONDS - start)) -lt $TANG_TIMEOUT ]; do
        for url in $TANG_URLS; do
            if curl -sf --max-time 5 "$url/adv" >/dev/null 2>&1; then
                log "Tang reachable: $url (after $((SECONDS - start))s)"
                return 0
            fi
        done
        sleep "$RETRY_INTERVAL"
    done

    log "Tang not reachable after ${TANG_TIMEOUT}s"
    return 1
}

unlock() {
    local dev=$1
    local name=$2

    if [ -e "/dev/mapper/$name" ]; then
        log "$name already open"
        return 0
    fi

    if timeout $UNLOCK_TIMEOUT clevis luks unlock -d "$dev" -n "$name" 2>>"$LOG"; then
        log "$name unlocked"
        return 0
    fi

    log "$name ERROR"
    return 1
}

log "=== Start unlock ==="

if wait_for_tang; then
    for entry in $LUKS_VOLUMES; do
        dev="${entry%%:*}"
        name="${entry##*:}"
        unlock "$dev" "$name"
    done
else
    log "Abort - No Tang server reachable"
fi

log "=== End ==="
