#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# HiringSpaces — container entrypoint
# Runs at ACI startup; target: VS Code accessible < 60 s
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

WORKSPACE=/home/coder/workspace
LOG=/home/coder/startup.log

log() { echo "[$(date -u +%T)] $*" | tee -a "$LOG"; }

log "=== HiringSpaces environment starting ==="

# ── 1. Pull latest code (repo already cloned in image layer) ─────────────────
log "Pulling latest repo changes..."
cd "$WORKSPACE"
git pull --ff-only origin main 2>&1 | tail -3 || log "WARN: git pull failed, using baked snapshot"

# ── 2. Accept any new session env vars passed by ACI ─────────────────────────
# CANDIDATE_ID and SESSION_TOKEN are injected by the HiringSpaces backend
# and can be used by the backend to identify the session.
log "Session: CANDIDATE_ID=${CANDIDATE_ID:-unknown}"

# ── 3. Optionally set a per-session workspace password ───────────────────────
# If SESSION_TOKEN is set, use it as the code-server password so the backend
# can proxy requests with token-based auth.
#if [[ -n "${SESSION_TOKEN:-}" ]]; then
#    sed -i "s/^auth: none/auth: password/" /home/coder/.config/code-server/config.yaml
#    sed -i "s/^password: .*/password: \"${SESSION_TOKEN}\"/" /home/coder/.config/code-server/config.yaml
#    log "Session token auth enabled"

# ── 4. Background: pre-build both projects (warms JVM/CLR, faster first run) ─
(
    log "Pre-building Java project..."
    mvn install -f "$WORKSPACE/Java/pom.xml" -q 2>&1 >> "$LOG" || true
    log "Java pre-build done"
) &

(
    log "Pre-building .NET project..."
    dotnet build "$WORKSPACE/DotNet/LruCache.sln" 2>&1 >> "$LOG" || true
    log ".NET pre-build done"
) &

# ── 5. Start code-server (foreground) ─────────────────────────────────────────
log "Starting code-server on :8080..."
exec code-server \
    --config /home/coder/.config/code-server/config.yaml \
    "$WORKSPACE"
