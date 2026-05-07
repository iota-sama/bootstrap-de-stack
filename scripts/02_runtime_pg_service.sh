#!/usr/bin/env bash
set -euo pipefail

# @description: Provisioning and Ignition of a PostgreSQL Runtime Service.
# @script: 02_runtime_pg_service.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT INHERITANCE & VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run via run_setup.sh}"
: "${PGDATA:?PGDATA is not set. Ensure 01_setup_pg_engine.sh ran.}"
: "${PG_BIN_PATH:?PG_BIN_PATH is not set. Ensure 01_setup_pg_engine.sh ran.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"
: "${REGISTRY_FILE:?REGISTRY_FILE is not set. Run via run_setup.sh}"

LAB_NAME=$(basename "$LAB_HOME")

# Port Discovery: Use existing or call port_manager
if [[ -z "${PG_PORT:-}" ]]; then
    echo "[INFO] PG_PORT not found. Discovering via port_manager.sh..."
    PG_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service postgres --lab-name "${LAB_NAME}")
    export PG_PORT
fi

# Validate port is numeric
if ! [[ "$PG_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Received non-numeric port: $PG_PORT"
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. CONFIGURATION (The "Include" Sidecar Pattern)
# -----------------------------------------------------------------------------

# Performance defaults (overridable via settings.env)
: "${PG_SHARED_BUFFERS:="128MB"}"
: "${PG_MAX_CONNECTIONS:="100"}"

PG_CUSTOM_CONF="${PGDATA}/custom_lab.conf"
PG_LOG_DIR="${LAB_HOME}/logs/postgres"
PG_RUN_DIR="${LAB_HOME}/run/postgres"

mkdir -p "${PG_LOG_DIR}"
mkdir -p "${PG_RUN_DIR}"

export PG_CUSTOM_CONF PG_LOG_DIR PG_RUN_DIR

# Universal settings (Standard for PG 12 through 18)
cat > "$PG_CUSTOM_CONF" <<EOF
# --- Lab Factory Settings for $LAB_NAME ---
port = $PG_PORT
listen_addresses = '${PG_LISTEN_ADDRESSES:=localhost}'
unix_socket_directories = '${PG_RUN_DIR}'
shared_buffers = ${PG_SHARED_BUFFERS}
max_connections = ${PG_MAX_CONNECTIONS}

# Runtime Logging
logging_collector = on
log_directory = '$PG_LOG_DIR'
log_filename = 'postgresql-%Y-%m-%d.log'
EOF

# Feature-flagged settings for Version 18+
if [[ "${PG_VERSION}" -ge 18 ]]; then
    echo "[INFO] Version 18+ detected. Applying Async I/O optimizations..."
    cat >> "$PG_CUSTOM_CONF" <<EOF

# PostgreSQL 18+ Specific Performance Tuning
# io_method = 'io_uring' is faster but requires modern Linux Kernels (6.x+)
io_method = 'worker'
io_workers = 4
EOF
fi

# Defensive linkage: only add include if not already present
if ! grep -q "custom_lab.conf" "${PGDATA}/postgresql.conf"; then
    echo "include = 'custom_lab.conf'" >> "${PGDATA}/postgresql.conf"
fi

# -----------------------------------------------------------------------------
# 3. IGNITION & HEALTH CHECK (60s Timeout)
# -----------------------------------------------------------------------------
if "${PG_BIN_PATH}/pg_isready" -p "$PG_PORT" -h localhost >/dev/null 2>&1; then
    echo "[INFO] PostgreSQL is already running on port $PG_PORT. Skipping ignition."
else
    echo "[INFO] Starting PostgreSQL on port $PG_PORT..."
    "${PG_BIN_PATH}/pg_ctl" -D "$PGDATA" -l "${PG_LOG_DIR}/startup.log" start

    TIMEOUT=60
    while ! "${PG_BIN_PATH}/pg_isready" -p "$PG_PORT" -h localhost >/dev/null 2>&1; do
        TIMEOUT=$((TIMEOUT - 1))
        if [[ "$TIMEOUT" -le 0 ]]; then
            echo "[ERROR] DB ignition timeout. Check $PG_LOG_DIR/startup.log"
            exit 1
        fi
        sleep 1
    done
fi

echo "[SUCCESS] Lab '$LAB_NAME' is active on Port $PG_PORT."