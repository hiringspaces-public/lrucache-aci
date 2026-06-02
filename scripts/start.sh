#!/usr/bin/env bash
set -euo pipefail

WORKSPACE=/home/coder/workspace
LOG=/home/coder/startup.log

log() { echo "[$(date -u +%T)] $*" | tee -a "$LOG"; }

log "=== HiringSpaces environment starting ==="

log "Pulling latest repo changes..."
cd "$WORKSPACE"
git pull --ff-only origin main 2>&1 | tail -3 || log "WARN: git pull failed, using baked snapshot"

log "Session: CANDIDATE_ID=${CANDIDATE_ID:-unknown}"

(
    log "Pre-building .NET project..."
    dotnet build "$WORKSPACE/DotNet/LruCache.sln" 2>&1 >> "$LOG" || true
    log ".NET pre-build done"
) &

log "Starting code-server on :8080..."
exec code-server \
    --config /home/coder/.config/code-server/config.yaml \
    "$WORKSPACE"