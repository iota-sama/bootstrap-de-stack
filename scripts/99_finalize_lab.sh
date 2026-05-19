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

: "${PG_PORT:?PG_PORT is not set.}"
: "${PGDATA:?PGDATA is not set.}"
: "${PG_BIN_PATH:?PG_BIN_PATH is not set.}"
: "${PG_RUNTIME_DIR:?PG_RUNTIME_DIR is not set.}"
: "${PG_LAB_DB:?PG_LAB_DB is not set.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set.}"

: "${AIRFLOW_RUNTIME_DIR:?AIRFLOW_RUNTIME_DIR is not set.}"

: "${CONNECT_RUNTIME_DIR:?CONNECT_RUNTIME_DIR is not set.}"
: "${SCHEMA_REGISTRY_RUNTIME_DIR:?SCHEMA_REGISTRY_RUNTIME_DIR is not set.}"
: "${KAFKA_RUNTIME_DIR:?KAFKA_RUNTIME_DIR is not set.}"
: "${KAFKA_BIN_PATH:?KAFKA_BIN_PATH is not set.}"

LAB_NAME=$(basename "$LAB_HOME")

# -----------------------------------------------------------------------------
# 2. GRACEFUL SHUTDOWN — AIRFLOW
# -----------------------------------------------------------------------------
echo "[INFO] Finalizing lab. Shutting down services for cold delivery..."

if [[ -f "${AIRFLOW_RUNTIME_DIR}/airflow-api-server.pid" ]]; then
    API_PID=$(cat "${AIRFLOW_RUNTIME_DIR}/airflow-api-server.pid")
    if kill -0 "${API_PID}" 2>/dev/null; then
        echo "[INFO] Stopping Airflow API server (PID: ${API_PID})..."
        kill "${API_PID}" 2>/dev/null || true
        sleep 2
        kill -0 "${API_PID}" 2>/dev/null && kill -9 "${API_PID}" 2>/dev/null || true
        rm -f "${AIRFLOW_RUNTIME_DIR}/airflow-api-server.pid"
        echo "[INFO] Airflow API server stopped."
    else
        rm -f "${AIRFLOW_RUNTIME_DIR}/airflow-api-server.pid"
    fi
fi

if [[ -f "${AIRFLOW_RUNTIME_DIR}/airflow-scheduler.pid" ]]; then
    SCHED_PID=$(cat "${AIRFLOW_RUNTIME_DIR}/airflow-scheduler.pid")
    if kill -0 "${SCHED_PID}" 2>/dev/null; then
        echo "[INFO] Stopping Airflow scheduler (PID: ${SCHED_PID})..."
        kill "${SCHED_PID}" 2>/dev/null || true
        sleep 2
        kill -0 "${SCHED_PID}" 2>/dev/null && kill -9 "${SCHED_PID}" 2>/dev/null || true
        rm -f "${AIRFLOW_RUNTIME_DIR}/airflow-scheduler.pid"
        echo "[INFO] Airflow scheduler stopped."
    else
        rm -f "${AIRFLOW_RUNTIME_DIR}/airflow-scheduler.pid"
    fi
fi

# -----------------------------------------------------------------------------
# 3. GRACEFUL SHUTDOWN — KAFKA CONNECT
# -----------------------------------------------------------------------------
if [[ -n "${CONNECT_RUNTIME_DIR:-}" ]] && [[ -f "${CONNECT_RUNTIME_DIR}/connect.pid" ]]; then
    CONNECT_PID=$(cat "${CONNECT_RUNTIME_DIR}/connect.pid")
    if kill -0 "${CONNECT_PID}" 2>/dev/null; then
        echo "[INFO] Stopping Kafka Connect (PID: ${CONNECT_PID})..."
        kill "${CONNECT_PID}" 2>/dev/null || true
        sleep 2
        kill -0 "${CONNECT_PID}" 2>/dev/null && kill -9 "${CONNECT_PID}" 2>/dev/null || true
        rm -f "${CONNECT_RUNTIME_DIR}/connect.pid"
        echo "[INFO] Kafka Connect stopped."
    else
        rm -f "${CONNECT_RUNTIME_DIR}/connect.pid"
    fi
fi

# -----------------------------------------------------------------------------
# 4. GRACEFUL SHUTDOWN — SCHEMA REGISTRY
# -----------------------------------------------------------------------------
if [[ -n "${SCHEMA_REGISTRY_RUNTIME_DIR:-}" ]] && [[ -f "${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid" ]]; then
    SR_PID=$(cat "${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid")
    if kill -0 "${SR_PID}" 2>/dev/null; then
        echo "[INFO] Stopping Schema Registry (PID: ${SR_PID})..."
        kill "${SR_PID}" 2>/dev/null || true
        sleep 2
        kill -0 "${SR_PID}" 2>/dev/null && kill -9 "${SR_PID}" 2>/dev/null || true
        rm -f "${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid"
        echo "[INFO] Schema Registry stopped."
    else
        rm -f "${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid"
    fi
fi

# -----------------------------------------------------------------------------
# 5. GRACEFUL SHUTDOWN — KAFKA BROKER
# -----------------------------------------------------------------------------
if [[ -n "${KAFKA_RUNTIME_DIR:-}" ]] && [[ -f "${KAFKA_RUNTIME_DIR}/kafka.pid" ]]; then
    KAFKA_PID=$(cat "${KAFKA_RUNTIME_DIR}/kafka.pid")
    if kill -0 "${KAFKA_PID}" 2>/dev/null; then
        echo "[INFO] Stopping Kafka broker (PID: ${KAFKA_PID})..."
        if [[ -n "${KAFKA_BIN_PATH:-}" ]] && [[ -f "${KAFKA_BIN_PATH}/kafka-server-stop.sh" ]]; then
            "${KAFKA_BIN_PATH}/kafka-server-stop.sh" 2>/dev/null || true
            sleep 3
        fi
        kill -0 "${KAFKA_PID}" 2>/dev/null && kill "${KAFKA_PID}" 2>/dev/null || true
        sleep 2
        kill -0 "${KAFKA_PID}" 2>/dev/null && kill -9 "${KAFKA_PID}" 2>/dev/null || true
        rm -f "${KAFKA_RUNTIME_DIR}/kafka.pid"
        echo "[INFO] Kafka broker stopped."
    else
        rm -f "${KAFKA_RUNTIME_DIR}/kafka.pid"
    fi
fi

# -----------------------------------------------------------------------------
# 6. WAL HEALTH CHECK (Informational — slot NOT dropped)
# -----------------------------------------------------------------------------
if [[ -n "${PG_BIN_PATH:-}" ]] && [[ -n "${PG_RUNTIME_DIR:-}" ]] && [[ -n "${PG_PORT:-}" ]] && [[ -n "${PG_LAB_DB:-}" ]]; then
    if "${PG_BIN_PATH}/pg_isready" -p "${PG_PORT}" -h localhost >/dev/null 2>&1; then
        echo "[INFO] Replication slot status:"
        "${PG_BIN_PATH}/psql" -h "${PG_RUNTIME_DIR}" -p "${PG_PORT}" -d "${PG_LAB_DB}" -t \
            -c "SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained, active FROM pg_replication_slots WHERE slot_name LIKE 'debezium_%';" \
            2>/dev/null || true
    fi
fi

# -----------------------------------------------------------------------------
# 7. GRACEFUL SHUTDOWN — POSTGRESQL
# -----------------------------------------------------------------------------
if "${PG_BIN_PATH}/pg_isready" -p "${PG_PORT}" -h localhost >/dev/null 2>&1; then
    echo "[INFO] Stopping PostgreSQL on port ${PG_PORT}..."
    "${PG_BIN_PATH}/pg_ctl" -D "${PGDATA}" stop -m fast
    echo "[INFO] PostgreSQL stopped."
else
    echo "[INFO] PostgreSQL is not running."
fi

# -----------------------------------------------------------------------------
# 8. FINAL SUMMARY
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