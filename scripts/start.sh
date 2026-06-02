#!/usr/bin/env bash
# Entrypoint: keep this resilient. Nothing here should ever exit non-zero
# before the final `exec code-server`, or ACI will restart-loop the container.
set -uo pipefail

WORKSPACE=/home/coder/workspace
LOG=/home/coder/startup.log

# Never block on a git credential prompt in a non-interactive container.
export GIT_TERMINAL_PROMPT=0
export DOTNET_CLI_TELEMETRY_OPTOUT=1

log() { echo "[$(date -u +%T)] $*" | tee -a "$LOG"; }

log "=== HiringSpaces environment starting ==="

log "Pulling latest repo changes..."
cd "$WORKSPACE" || log "WARN: workspace $WORKSPACE missing"
timeout 20 git pull --ff-only origin main 2>&1 | tail -3 \
    || log "WARN: git pull failed/timed out, using baked snapshot"

# Ensure the whole workspace is owned by coder. The image's build-time
# `dotnet restore` runs as root and leaves root-owned obj/ dirs, which makes a
# runtime restore/build fail with "Access to the path ... is denied". Never
# let this abort startup.
log "Fixing workspace ownership..."
sudo -n chown -R coder:coder "$WORKSPACE" 2>/dev/null \
    || chown -R coder:coder "$WORKSPACE" 2>/dev/null \
    || log "WARN: could not chown $WORKSPACE (continuing anyway)"

mkdir -p /home/coder/.config/code-server

# Create config if missing (image bakes one in; this is a fallback)
if [[ ! -f /home/coder/.config/code-server/config.yaml ]]; then
    cat > /home/coder/.config/code-server/config.yaml << 'EOF'
bind-addr: 0.0.0.0:8080
auth: none
cert: false
EOF
fi

log "Session: CANDIDATE_ID=${CANDIDATE_ID:-unknown}"

# Optional pre-build. Auto-detects the stack so one start.sh works for both the
# .NET and Java images. Backgrounded and memory-capped so it can NEVER take down
# code-server (PID 1). Skip entirely on small instances by setting SKIP_PREBUILD=1.
if [[ "${SKIP_PREBUILD:-0}" != "1" ]]; then
(
    if command -v dotnet >/dev/null && [[ -f "$WORKSPACE/DotNet/LruCache.sln" ]]; then
        log "Pre-building .NET project..."
        DOTNET_GCHeapHardLimit=0xC0000000 \
            dotnet build "$WORKSPACE/DotNet/LruCache.sln" -m:1 >> "$LOG" 2>&1 \
            || log "WARN: .NET pre-build failed (candidate can still build manually)"
        log ".NET pre-build done"
    elif command -v mvn >/dev/null && [[ -f "$WORKSPACE/Java/pom.xml" ]]; then
        log "Pre-building Java project..."
        mvn -q -f "$WORKSPACE/Java/pom.xml" install -DskipTests >> "$LOG" 2>&1 \
            || log "WARN: Java pre-build failed (candidate can still build manually)"
        log "Java pre-build done"
    fi
) &
fi

CODE_SERVER=$(command -v code-server || true)
if [[ -z "$CODE_SERVER" ]]; then
    log "ERROR: code-server not found in PATH"
    exit 1
fi

log "Starting code-server on :8080..."
# Open the baked .code-workspace file (per-language settings + files.exclude that
# hides the other language and infra files). Fall back to the folder if missing.
WORKSPACE_FILE="$WORKSPACE/lrucache.code-workspace"
if [[ -f "$WORKSPACE_FILE" ]]; then
    OPEN_TARGET="$WORKSPACE_FILE"
else
    OPEN_TARGET="$WORKSPACE"
fi
exec "$CODE_SERVER" \
    --config /home/coder/.config/code-server/config.yaml \
    "$OPEN_TARGET"
