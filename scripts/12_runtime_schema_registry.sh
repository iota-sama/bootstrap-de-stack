#!/usr/bin/env bash
set -euo pipefail

# @description: Start Apicurio Schema Registry with Kafka-backed storage.
# @script: 12_runtime_schema_registry.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT INHERITANCE & VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set.}"
: "${SCHEMA_REGISTRY_HOME:?Ensure 11_setup_schema_registry.sh ran.}"
: "${SCHEMA_REGISTRY_LOG_DIR:?Ensure 11_setup_schema_registry.sh ran.}"
: "${SCHEMA_REGISTRY_RUNTIME_DIR:?Ensure 11_setup_schema_registry.sh ran.}"
: "${KAFKA_PORT:?KAFKA_PORT not set. Ensure 10_runtime_kafka.sh ran.}"
: "${KAFKA_BIN_PATH:?KAFKA_BIN_PATH not set. Ensure 09_setup_kafka.sh ran.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set.}"
: "${REGISTRY_FILE:?REGISTRY_FILE is not set.}"
: "${JAVA_HOME:?JAVA_HOME not set.}"
: "${STACK_ID:?STACK_ID not set.}"
: "${SECRET_FILE:="${LAB_HOME}/secrets/generated.env"}"

LAB_NAME=$(basename "$LAB_HOME")
source "${SECRET_FILE}"

# -----------------------------------------------------------------------------
# 2. VALIDATE KAFKA DEPENDENCY
# -----------------------------------------------------------------------------
echo "[INFO] Validating Kafka broker before starting Schema Registry..."

if ! echo > "/dev/tcp/localhost/${KAFKA_PORT}" 2>&1 >/dev/null; then
    echo "[ERROR] Kafka broker not reachable on port ${KAFKA_PORT}."
    exit 1
fi


# -----------------------------------------------------------------------------
# 3. PORT DISCOVERY
# -----------------------------------------------------------------------------
SCHEMA_REGISTRY_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service schema_registry --lab-name "${LAB_NAME}")
export SCHEMA_REGISTRY_PORT

if ! [[ "$SCHEMA_REGISTRY_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid Schema Registry port: $SCHEMA_REGISTRY_PORT"
    exit 1
fi

SCHEMA_REGISTRY_MANAGEMENT_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service schema_registry_management --lab-name "${LAB_NAME}")
export SCHEMA_REGISTRY_MANAGEMENT_PORT

if ! [[ "$SCHEMA_REGISTRY_MANAGEMENT_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid Schema Registry management port: $SCHEMA_REGISTRY_MANAGEMENT_PORT"
    exit 1
fi

echo "[INFO] Schema Registry ports - Application: ${SCHEMA_REGISTRY_PORT}, Management: ${SCHEMA_REGISTRY_MANAGEMENT_PORT})"

# -----------------------------------------------------------------------------
# 4. DEFAULTS
# -----------------------------------------------------------------------------
: "${SCHEMA_REGISTRY_HEAP_OPTS:="-Xmx256M -Xms128M"}"
SCHEMA_REGISTRY_URL="http://localhost:${SCHEMA_REGISTRY_PORT}"
: "${SCHEMA_REGISTRY_COMPAT_URL:="http://localhost:${SCHEMA_REGISTRY_PORT}/apis/ccompat/v7"}"

# -----------------------------------------------------------------------------
# 5. START SCHEMA REGISTRY (Idempotent)
# -----------------------------------------------------------------------------
SCHEMA_REGISTRY_PID_FILE="${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid"

REGISTRY_RUNNING=false
if [[ -f "${SCHEMA_REGISTRY_PID_FILE}" ]]; then
    SR_PID_VAL=$(cat "${SCHEMA_REGISTRY_PID_FILE}")
    if kill -0 "${SR_PID_VAL}" 2>/dev/null; then
        echo "[INFO] Schema Registry already running (PID: ${SR_PID_VAL}). Skipping."
        REGISTRY_RUNNING=true
    else
        echo "[INFO] Stale PID file found. Restarting..."
        rm -f "${SCHEMA_REGISTRY_PID_FILE}"
    fi
fi

if [[ "${REGISTRY_RUNNING}" == "false" ]]; then
    echo "[INFO] Starting Apicurio Schema Registry..."

    export KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_PORT}"
    export APICURIO_STORAGE_KAFKA_BOOTSTRAP_SERVERS="localhost:${KAFKA_PORT}"
    export QUARKUS_HTTP_PORT="${SCHEMA_REGISTRY_PORT}"
    export QUARKUS_MANAGEMENT_PORT="${SCHEMA_REGISTRY_MANAGEMENT_PORT}"
    export QUARKUS_LOG_LEVEL="INFO"

    nohup "${JAVA_HOME}/bin/java" ${SCHEMA_REGISTRY_HEAP_OPTS} \
        -jar "${SCHEMA_REGISTRY_HOME}/quarkus-app/quarkus-run.jar" \
        > "${SCHEMA_REGISTRY_LOG_DIR}/schema-registry.log" 2>&1 &

    SCHEMA_REGISTRY_PID=$!
    echo "${SCHEMA_REGISTRY_PID}" > "${SCHEMA_REGISTRY_PID_FILE}"
    echo "[SUCCESS] Schema Registry starting (PID: ${SCHEMA_REGISTRY_PID})."
fi

# -----------------------------------------------------------------------------
# 6. HEALTH CHECK — MANAGEMENT INTERFACE (30s Timeout)
# -----------------------------------------------------------------------------
echo "[INFO] Health check on Schema Registry (management port ${SCHEMA_REGISTRY_MANAGEMENT_PORT})..."
TIMEOUT=30
REGISTRY_HEALTHY=false

while [[ "${TIMEOUT}" -gt 0 ]]; do
    if curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:${SCHEMA_REGISTRY_MANAGEMENT_PORT}/health/ready" \
        2>/dev/null | grep -q "200"; then
        REGISTRY_HEALTHY=true
        break
    fi
    TIMEOUT=$((TIMEOUT - 1))
    sleep 1
done

if [[ "${REGISTRY_HEALTHY}" == "false" ]]; then
    echo "[ERROR] Schema Registry failed health check within 30 seconds."
    echo "Check logs: ${SCHEMA_REGISTRY_LOG_DIR}/schema-registry.log"
    exit 1
fi

echo "[INFO] Schema Registry healthy."

# -----------------------------------------------------------------------------
# 7. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
export SCHEMA_REGISTRY_PORT
export SCHEMA_REGISTRY_MANAGEMENT_PORT
export SCHEMA_REGISTRY_PID_FILE
export SCHEMA_REGISTRY_RUNTIME_DIR
export SCHEMA_REGISTRY_LOG_DIR
export SCHEMA_REGISTRY_URL
export SCHEMA_REGISTRY_COMPAT_URL

echo "[SUCCESS] Script 12: Schema Registry active."
echo "  Schema Registry API: ${SCHEMA_REGISTRY_URL}"
echo "  Confluent Compatible Schema Registry API: ${SCHEMA_REGISTRY_COMPAT_URL}"
