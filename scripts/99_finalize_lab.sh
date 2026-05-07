#!/usr/bin/env bash
set -euo pipefail

# @description: Finalizes the lab by gracefully shutting down all services.
#              Delivers the lab in a COLD state — ready for the user to start.
# @script: 99_finalize_lab.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run base setup first.}"
: "${STACK_ID:?STACK_ID is not set.}"
: "${ENV_NAME:?ENV_NAME is not set.}"

# PostgreSQL variables
: "${PG_PORT:?PG_PORT is not set. Ensure 02_runtime_pg_service.sh ran.}"
: "${PGDATA:?PGDATA is not set. Ensure 01_setup_pg_engine.sh ran.}"
: "${PG_BIN_PATH:?PG_BIN_PATH is not set. Ensure 01_setup_pg_engine.sh ran.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"

# Airflow variables
: "${AIRFLOW_RUN_DIR:?AIRFLOW_RUN_DIR is not set.}"

LAB_NAME=$(basename "$LAB_HOME")

# -----------------------------------------------------------------------------
# 2. GRACEFUL SHUTDOWN — AIRFLOW
# -----------------------------------------------------------------------------
echo "[INFO] Finalizing lab. Shutting down services for cold delivery..."

# Stop Airflow API server
if [[ -f "${AIRFLOW_RUN_DIR}/airflow-api-server.pid" ]]; then
    API_PID=$(cat "${AIRFLOW_RUN_DIR}/airflow-api-server.pid")
    if kill -0 "${API_PID}" 2>/dev/null; then
        echo "[INFO] Stopping Airflow API server (PID: ${API_PID})..."
        kill "${API_PID}" 2>/dev/null || true
        sleep 2
        if kill -0 "${API_PID}" 2>/dev/null; then
            echo "[WARN] Force stopping Airflow API server..."
            kill -9 "${API_PID}" 2>/dev/null || true
        fi
        rm -f "${AIRFLOW_RUN_DIR}/airflow-api-server.pid"
        echo "[INFO] Airflow API server stopped."
    else
        rm -f "${AIRFLOW_RUN_DIR}/airflow-api-server.pid"
    fi
fi

# Stop Airflow scheduler
if [[ -f "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid" ]]; then
    SCHED_PID=$(cat "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid")
    if kill -0 "${SCHED_PID}" 2>/dev/null; then
        echo "[INFO] Stopping Airflow scheduler (PID: ${SCHED_PID})..."
        kill "${SCHED_PID}" 2>/dev/null || true
        sleep 2
        if kill -0 "${SCHED_PID}" 2>/dev/null; then
            echo "[WARN] Force stopping Airflow scheduler..."
            kill -9 "${SCHED_PID}" 2>/dev/null || true
        fi
        rm -f "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid"
        echo "[INFO] Airflow scheduler stopped."
    else
        rm -f "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid"
    fi
fi

# -----------------------------------------------------------------------------
# 3. GRACEFUL SHUTDOWN — POSTGRESQL
# -----------------------------------------------------------------------------
if "${PG_BIN_PATH}/pg_isready" -p "${PG_PORT}" -h localhost >/dev/null 2>&1; then
    echo "[INFO] Stopping PostgreSQL on port ${PG_PORT}..."
    "${PG_BIN_PATH}/pg_ctl" -D "${PGDATA}" stop -m fast
    echo "[INFO] PostgreSQL stopped."
else
    echo "[INFO] PostgreSQL is not running."
fi

# -----------------------------------------------------------------------------
# 4. FINAL SUMMARY
# -----------------------------------------------------------------------------
echo "======================================================="
echo "[COMPLETE] DE Lab Factory provisioning finished."
echo "Lab Name:    ${LAB_NAME}"
echo "Lab ID:      ${STACK_ID}"
echo "Environment: ${ENV_NAME}"
echo "Location:    ${LAB_HOME}"
echo ""
echo "Start Lab:   source ${LAB_HOME}/bin/lab_entry.sh"
echo "Stop Lab:    bash ${LAB_HOME}/bin/lab_shutdown.sh"
echo "Delete Lab:  bash ${BOOTSTRAP_DIR}/utils/delete_lab.sh --lab-path ${LAB_HOME}"
echo "======================================================="

echo "[SUCCESS] Lab delivered in cold state. All services stopped."
