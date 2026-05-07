#!/usr/bin/env bash
set -euo pipefail

# @description: Discover port, start Airflow scheduler and API server, run health checks.
# @script: 07_runtime_airflow.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT INHERITANCE & VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run via run_setup.sh}"
: "${AIRFLOW_VENV:?AIRFLOW_VENV is not set. Ensure 04_setup_airflow_venv.sh ran.}"
: "${AIRFLOW_HOME:?AIRFLOW_HOME is not set. Ensure 04_setup_airflow_venv.sh ran.}"
: "${AIRFLOW_CFG:?AIRFLOW_CFG is not set. Ensure 06_configure_airflow.sh ran.}"
: "${AIRFLOW_DAGS_FOLDER:?AIRFLOW_DAGS_FOLDER is not set. Ensure 06_configure_airflow.sh ran.}"
: "${AIRFLOW_DB_USER:?AIRFLOW_DB_USER is not set. Ensure 05_provision_airflow_db.sh ran.}"
: "${AIRFLOW_DB_PASS:?AIRFLOW_DB_PASS is not set. Ensure 05_provision_airflow_db.sh ran.}"
: "${AIRFLOW_DB_NAME:?AIRFLOW_DB_NAME is not set. Ensure 05_provision_airflow_db.sh ran.}"
: "${PG_PORT:?PG_PORT is not set. Ensure 02_runtime_pg_service.sh ran.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"
: "${REGISTRY_FILE:?REGISTRY_FILE is not set. Run via run_setup.sh}"

LAB_NAME=$(basename "$LAB_HOME")

# -----------------------------------------------------------------------------
# 2. PORT DISCOVERY
# -----------------------------------------------------------------------------
if [[ -z "${AIRFLOW_PORT:-}" ]]; then
    echo "[INFO] AIRFLOW_PORT not found. Discovering via port_manager.sh..."
    AIRFLOW_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service airflow --lab-name "${LAB_NAME}")
    export AIRFLOW_PORT
fi

# Validate port is numeric
if ! [[ "$AIRFLOW_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Received non-numeric port: $AIRFLOW_PORT"
    exit 1
fi

echo "[INFO] Airflow API server will use port: ${AIRFLOW_PORT}"

# -----------------------------------------------------------------------------
# 3. SETUP AIRFLOW ENVIRONMENT
# -----------------------------------------------------------------------------
# Ensure variables are available (defensive: supports standalone execution)
: "${AIRFLOW_HOME:="${LAB_HOME}/configs"}"
export AIRFLOW_HOME

: "${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN:="postgresql://${AIRFLOW_DB_USER}:${AIRFLOW_DB_PASS}@localhost:${PG_PORT}/${AIRFLOW_DB_NAME}"}"
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN

# Set the API server port (discovered in Section 2)
export AIRFLOW__API__PORT="${AIRFLOW_PORT}"

# Runtime directories (idempotent)
AIRFLOW_LOG_DIR="${LAB_HOME}/logs/airflow"
AIRFLOW_RUN_DIR="${LAB_HOME}/run/airflow"
mkdir -p "${AIRFLOW_LOG_DIR}"
mkdir -p "${AIRFLOW_RUN_DIR}"

# PID file paths for process management
AIRFLOW_API_SERVER_PID="${AIRFLOW_RUN_DIR}/airflow-api-server.pid"
AIRFLOW_SCHEDULER_PID="${AIRFLOW_RUN_DIR}/airflow-scheduler.pid"


# -----------------------------------------------------------------------------
# 4. START AIRFLOW SCHEDULER (Idempotent)
# -----------------------------------------------------------------------------
echo "[INFO] Starting Airflow scheduler..."

SCHEDULER_RUNNING=false
if [[ -f "${AIRFLOW_SCHEDULER_PID}" ]]; then
    SCHEDULER_PID_VAL=$(cat "${AIRFLOW_SCHEDULER_PID}")
    if kill -0 "${SCHEDULER_PID_VAL}" 2>/dev/null; then
        echo "[INFO] Airflow scheduler is already running (PID: ${SCHEDULER_PID_VAL}). Skipping."
        SCHEDULER_RUNNING=true
    else
        echo "[INFO] Stale PID file found. Removing and restarting..."
        rm -f "${AIRFLOW_SCHEDULER_PID}"
    fi
fi

if [[ "${SCHEDULER_RUNNING}" == "false" ]]; then
    "${AIRFLOW_VENV}/bin/airflow" scheduler \
        --pid "${AIRFLOW_SCHEDULER_PID}" \
        --stdout "${AIRFLOW_LOG_DIR}/scheduler.log" \
        --stderr "${AIRFLOW_LOG_DIR}/scheduler_error.log" \
        -D

    echo "[SUCCESS] Airflow scheduler started."
fi

# -----------------------------------------------------------------------------
# 5. START AIRFLOW API SERVER (Idempotent)
# -----------------------------------------------------------------------------
echo "[INFO] Starting Airflow API server on port ${AIRFLOW_PORT}..."

API_SERVER_RUNNING=false
if [[ -f "${AIRFLOW_API_SERVER_PID}" ]]; then
    API_SERVER_PID_VAL=$(cat "${AIRFLOW_API_SERVER_PID}")
    if kill -0 "${API_SERVER_PID_VAL}" 2>/dev/null; then
        echo "[INFO] Airflow API server is already running (PID: ${API_SERVER_PID_VAL}). Skipping."
        API_SERVER_RUNNING=true
    else
        echo "[INFO] Stale PID file found. Removing and restarting..."
        rm -f "${AIRFLOW_API_SERVER_PID}"
    fi
fi

if [[ "${API_SERVER_RUNNING}" == "false" ]]; then
    "${AIRFLOW_VENV}/bin/airflow" api-server \
        --port "${AIRFLOW_PORT}" \
        --pid "${AIRFLOW_API_SERVER_PID}" \
        --stdout "${AIRFLOW_LOG_DIR}/api-server.log" \
        --stderr "${AIRFLOW_LOG_DIR}/api-server_error.log" \
        -D

    echo "[SUCCESS] Airflow API server started."
fi

# -----------------------------------------------------------------------------
# 6. HEALTH CHECK — SCHEDULER (30s Timeout)
# -----------------------------------------------------------------------------
echo "[INFO] Performing health check on Airflow scheduler..."
TIMEOUT=30
SCHEDULER_HEALTHY=false

while [[ "${TIMEOUT}" -gt 0 ]]; do
    if [[ -f "${AIRFLOW_SCHEDULER_PID}" ]]; then
        SCHEDULER_PID_VAL=$(cat "${AIRFLOW_SCHEDULER_PID}")
        if kill -0 "${SCHEDULER_PID_VAL}" 2>/dev/null; then
            SCHEDULER_HEALTHY=true
            break
        fi
    fi
    TIMEOUT=$((TIMEOUT - 1))
    sleep 1
done

if [[ "${SCHEDULER_HEALTHY}" == "false" ]]; then
    echo "[ERROR] Airflow scheduler failed to start within 30 seconds."
    echo "Check logs: ${AIRFLOW_LOG_DIR}/scheduler.log"
    exit 1
fi

echo "[INFO] Airflow scheduler is healthy."

# -----------------------------------------------------------------------------
# 7. HEALTH CHECK — API SERVER (30s Timeout)
# -----------------------------------------------------------------------------
echo "[INFO] Performing health check on Airflow API server..."
TIMEOUT=30
API_SERVER_HEALTHY=false

while [[ "${TIMEOUT}" -gt 0 ]]; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${AIRFLOW_PORT}/api/v2/monitor/health" 2>/dev/null | grep -q "200"; then
        API_SERVER_HEALTHY=true
        break
    fi
    TIMEOUT=$((TIMEOUT - 1))
    sleep 1
done

if [[ "${API_SERVER_HEALTHY}" == "false" ]]; then
    echo "[ERROR] Airflow API server failed to start within 30 seconds."
    echo "Check logs: ${AIRFLOW_LOG_DIR}/api-server.log"
    exit 1
fi

echo "[INFO] Airflow API server is healthy."

# -----------------------------------------------------------------------------
# 8. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
export AIRFLOW_PORT
export AIRFLOW_API_SERVER_PID
export AIRFLOW_SCHEDULER_PID
export AIRFLOW_LOG_DIR
export AIRFLOW_RUN_DIR

echo "[SUCCESS] Script 07: Airflow runtime is active."
echo "  API Server: http://localhost:${AIRFLOW_PORT}"
echo "  Scheduler:  PID ${SCHEDULER_PID_VAL}"
echo "  Logs:       ${AIRFLOW_LOG_DIR}"
