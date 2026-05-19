#!/usr/bin/env bash
set -euo pipefail

# @description: Generate server.properties, configure SASL/PLAIN, start Kafka broker.
# @script: 10_runtime_kafka.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT INHERITANCE & VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run via run_setup.sh}"
: "${KAFKA_HOME:?KAFKA_HOME is not set. Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_DATA_DIR:?KAFKA_DATA_DIR is not set. Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_BIN_PATH:?KAFKA_BIN_PATH is not set. Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_LOG_DIR:?KAFKA_LOG_DIR is not set. Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_RUNTIME_DIR:?KAFKA_RUNTIME_DIR is not set. Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_CONFIG_DIR:?KAFKA_CONFIG_DIR is not set. Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_CLUSTER_ID:?KAFKA_CLUSTER_ID is not set. Ensure 09_setup_kafka.sh ran.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"
: "${REGISTRY_FILE:?REGISTRY_FILE is not set. Run via run_setup.sh}"
: "${JAVA_HOME:?JAVA_HOME is not set. Ensure 08_setup_java.sh ran.}"
: "${STACK_ID:?STACK_ID is not set. Ensure 00_base_setup.sh ran.}"
: "${SECRET_FILE:="${LAB_HOME}/secrets/generated.env"}"

LAB_NAME=$(basename "$LAB_HOME")
STACK_ID_SHORT="${STACK_ID:0:8}"
source "${SECRET_FILE}"

# -----------------------------------------------------------------------------
# 2. PORT DISCOVERY
# -----------------------------------------------------------------------------
KAFKA_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service kafka_broker --lab-name "${LAB_NAME}")
export KAFKA_PORT

if ! [[ "$KAFKA_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid Kafka broker port: $KAFKA_PORT"
    exit 1
fi

KAFKA_CONTROLLER_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service kafka_controller --lab-name "${LAB_NAME}")
export KAFKA_CONTROLLER_PORT

if ! [[ "$KAFKA_CONTROLLER_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid Kafka controller port: $KAFKA_CONTROLLER_PORT"
    exit 1
fi

KAFKA_INTERNAL_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service kafka_internal --lab-name "${LAB_NAME}")
export KAFKA_INTERNAL_PORT

if ! [[ "$KAFKA_INTERNAL_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid Kafka internal port: $KAFKA_INTERNAL_PORT"
    exit 1
fi

echo "[INFO] Kafka ports — Broker: ${KAFKA_PORT}, Controller: ${KAFKA_CONTROLLER_PORT}, Internal: ${KAFKA_INTERNAL_PORT}"

# -----------------------------------------------------------------------------
# 3. DEFAULTS & CONFIGURATION
# -----------------------------------------------------------------------------
: "${KAFKA_HEAP_OPTS:="-Xmx512M -Xms256M"}"
: "${KAFKA_LOG_RETENTION_HOURS:="72"}"
: "${KAFKA_ENABLE_SASL:="true"}"
: "${KAFKA_ADMIN_USER_PREFIX:="kafka_admin"}"

KAFKA_LOG_DIRS="${KAFKA_DATA_DIR}/logs"

# -----------------------------------------------------------------------------
# 4. GENERATE SASL CREDENTIALS
# -----------------------------------------------------------------------------
if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
    if ! grep -q "KAFKA_ADMIN_USER" "${SECRET_FILE}"; then
        KAFKA_ADMIN_USER="${KAFKA_ADMIN_USER_PREFIX}_${STACK_ID_SHORT}"
        KAFKA_ADMIN_PASS=$(openssl rand -base64 12)

        cat >> "${SECRET_FILE}" <<EOF

# Kafka Admin Credentials
KAFKA_ADMIN_USER='${KAFKA_ADMIN_USER}'
KAFKA_ADMIN_PASS='${KAFKA_ADMIN_PASS}'
EOF

        source "${SECRET_FILE}"
        echo "[SUCCESS] Kafka admin credentials generated."
    else
        : "${KAFKA_ADMIN_USER:?KAFKA_ADMIN_USER missing from secrets.}"
        : "${KAFKA_ADMIN_PASS:?KAFKA_ADMIN_PASS missing from secrets.}"
        echo "[INFO] Kafka admin credentials already exist."
    fi
fi

# -----------------------------------------------------------------------------
# 5. GENERATE JAAS CONFIGURATION (SASL)
# -----------------------------------------------------------------------------
KAFKA_JAAS_FILE="${KAFKA_CONFIG_DIR}/kafka_jaas.conf"

if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
    OLD_UMASK=$(umask)
    umask 077
    cat > "${KAFKA_JAAS_FILE}" <<EOF
KafkaServer {
    org.apache.kafka.common.security.plain.PlainLoginModule required
    username="${KAFKA_ADMIN_USER}"
    password="${KAFKA_ADMIN_PASS}"
    user_${KAFKA_ADMIN_USER}="${KAFKA_ADMIN_PASS}";
};
EOF
    umask "${OLD_UMASK}"
    echo "[INFO] JAAS configuration generated for SASL/PLAIN."
fi

# -----------------------------------------------------------------------------
# 6. GENERATE server.properties
# -----------------------------------------------------------------------------
echo "[INFO] Generating Kafka server.properties..."

if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
    SECURITY_PROTOCOL="SASL_PLAINTEXT"
else
    SECURITY_PROTOCOL="PLAINTEXT"
fi

cat > "${KAFKA_CONFIG_DIR}/server.properties" <<EOF
# ==========================================================
# Kafka Broker Configuration — bootstrap-de-stack
# Lab: ${ENV_NAME} (${STACK_ID})
# ==========================================================

# --- KRaft Single-Node ---
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@localhost:${KAFKA_CONTROLLER_PORT}

# --- Listeners ---
listeners=CLIENT://localhost:${KAFKA_PORT},INTERNAL://localhost:${KAFKA_INTERNAL_PORT},CONTROLLER://localhost:${KAFKA_CONTROLLER_PORT}
advertised.listeners=CLIENT://localhost:${KAFKA_PORT},INTERNAL://localhost:${KAFKA_INTERNAL_PORT}
listener.security.protocol.map=CLIENT:${SECURITY_PROTOCOL},INTERNAL:${SECURITY_PROTOCOL},CONTROLLER:PLAINTEXT
inter.broker.listener.name=INTERNAL
controller.listener.names=CONTROLLER



# --- SASL Authentication ---
sasl.enabled.mechanisms=PLAIN
sasl.mechanism.inter.broker.protocol=PLAIN

# --- Data Storage ---
log.dirs=${KAFKA_LOG_DIRS}
num.partitions=3

# --- Single-Node Replication ---
offsets.topic.replication.factor=1
transaction.state.log.replication.factor=1
transaction.state.log.min.isr=1
default.replication.factor=1
min.insync.replicas=1

# --- Log Retention ---
log.retention.hours=${KAFKA_LOG_RETENTION_HOURS}
log.segment.bytes=1073741824
EOF

echo "[SUCCESS] server.properties generated."

# -----------------------------------------------------------------------------
# 7. START KAFKA BROKER
# -----------------------------------------------------------------------------
KAFKA_PID_FILE="${KAFKA_RUNTIME_DIR}/kafka.pid"

BROKER_RUNNING=false
if [[ -f "${KAFKA_PID_FILE}" ]]; then
    KAFKA_PID_VAL=$(cat "${KAFKA_PID_FILE}")
    if kill -0 "${KAFKA_PID_VAL}" 2>/dev/null; then
        echo "[INFO] Kafka broker already running (PID: ${KAFKA_PID_VAL}). Skipping."
        BROKER_RUNNING=true
    else
        echo "[INFO] Stale PID file found. Restarting..."
        rm -f "${KAFKA_PID_FILE}"
    fi
fi

if [[ "${BROKER_RUNNING}" == "false" ]]; then
    echo "[INFO] Starting Kafka broker..."
    export KAFKA_HEAP_OPTS="${KAFKA_HEAP_OPTS}"
    if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
        export KAFKA_OPTS="-Djava.security.auth.login.config=${KAFKA_JAAS_FILE}"
    fi
    export LOG_DIR="${KAFKA_LOG_DIR}"

    nohup "${KAFKA_BIN_PATH}/kafka-server-start.sh" \
        "${KAFKA_CONFIG_DIR}/server.properties" \
        > "${KAFKA_LOG_DIR}/kafka-startup.log" 2>&1 &

    KAFKA_PID=$!
    echo "${KAFKA_PID}" > "${KAFKA_PID_FILE}"
    echo "[SUCCESS] Kafka broker starting (PID: ${KAFKA_PID})."
fi

# -----------------------------------------------------------------------------
# 8. HEALTH CHECK (60s Timeout)
# -----------------------------------------------------------------------------
echo "[INFO] Health check on Kafka broker..."
TIMEOUT=60
BROKER_HEALTHY=false

while [[ "${TIMEOUT}" -gt 0 ]]; do
    if echo > "/dev/tcp/localhost/${KAFKA_PORT}" 2>&1 >/dev/null; then
        BROKER_HEALTHY=true
        break
    fi
    TIMEOUT=$((TIMEOUT - 1))
    sleep 1
done

if [[ "${BROKER_HEALTHY}" == "false" ]]; then
    echo "[ERROR] Kafka broker failed to start within 60 seconds."
    echo "Check logs: ${KAFKA_LOG_DIR}/kafka-startup.log"
    exit 1
fi

echo "[INFO] Kafka broker healthy."

# -----------------------------------------------------------------------------
# 9. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
export KAFKA_PORT
export KAFKA_INTERNAL_PORT
export KAFKA_CONTROLLER_PORT
export KAFKA_PID_FILE
export KAFKA_RUNTIME_DIR
export KAFKA_LOG_DIR
export KAFKA_CONFIG_DIR
export KAFKA_DATA_DIR
export KAFKA_HOME
export KAFKA_JAAS_FILE
export KAFKA_ADMIN_USER
export KAFKA_ADMIN_PASS
export KAFKA_ENABLE_SASL


echo "[SUCCESS] Script 10: Kafka runtime active on port ${KAFKA_PORT}."
