#!/bin/bash

LOG=/var/log/unlock-lxc.log
TANG_URL="https://tang.example.com"  # Change to your tang server URL
TANG_TIMEOUT=60
UNLOCK_TIMEOUT=15

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"
}

wait_for_tang() {
    local i=0
    
    while [ $i -lt $TANG_TIMEOUT ]; do
        if curl -sf --max-time 5 "$TANG_URL/adv" >/dev/null 2>&1; then
            log "Tang reachable after ${i}s"
            return 0
        fi
        sleep 1
        ((i++))
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
    unlock /dev/pve/lxc-<CTID>-<NAME> lxc-<CTID>-<NAME>
    unlock /dev/pve/lxc-<CTID>-<NAME> lxc-<CTID>-<NAME>
else
    log "Abort - Tang service not reachable"
fi

log "=== End ==="