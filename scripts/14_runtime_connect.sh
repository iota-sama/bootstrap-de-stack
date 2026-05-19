#!/usr/bin/env bash
set -euo pipefail

# @description: Start Kafka Connect, configure Debezium CDC with Avro serialization.
# @script: 14_runtime_connect.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT INHERITANCE & VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set.}"
: "${CONNECT_PLUGIN_DIR:?Ensure 13_setup_connect.sh ran.}"
: "${CONNECT_LOG_DIR:?Ensure 13_setup_connect.sh ran.}"
: "${CONNECT_RUNTIME_DIR:?Ensure 13_setup_connect.sh ran.}"
: "${CONNECT_CONFIG_DIR:?Ensure 13_setup_connect.sh ran.}"
: "${KAFKA_HOME:?Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_BIN_PATH:?Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_PORT:?Ensure 10_runtime_kafka.sh ran.}"
: "${SCHEMA_REGISTRY_PORT:?Ensure 12_runtime_schema_registry.sh ran.}"
: "${STACK_ID:?STACK_ID is not set.}"
: "${PG_PORT:?PG_PORT not set.}"
: "${PG_LAB_DB:?PG_LAB_DB not set.}"
: "${PG_RUNTIME_DIR:?PG_RUNTIME_DIR not set.}"
: "${PG_BIN_PATH:?PG_BIN_PATH not set.}"
: "${SECRET_FILE:="${LAB_HOME}/secrets/generated.env"}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set.}"
: "${REGISTRY_FILE:?REGISTRY_FILE is not set.}"
: "${JAVA_HOME:?JAVA_HOME not set.}"
: "${KAFKA_ENABLE_SASL:?KAFKA_ENABLE_SASL not set.}"
: "${SCHEMA_REGISTRY_COMPAT_URL:?SCHEMA_REGISTRY_COMPAT_URL not set. Ensure 12_runtime_schema_registry.sh ran.}"


LAB_NAME=$(basename "$LAB_HOME")
STACK_ID_SHORT="${STACK_ID:0:8}"
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
CONNECT_PORT=$("${BOOTSTRAP_DIR}/utils/port_manager.sh" --service kafka_connect --lab-name "${LAB_NAME}")
export CONNECT_PORT

if ! [[ "$CONNECT_PORT" =~ ^[0-9]+$ ]]; then
    echo "[ERROR] Invalid Connect port: $CONNECT_PORT"
    exit 1
fi

echo "[INFO] Kafka Connect REST API port: ${CONNECT_PORT}"

# -----------------------------------------------------------------------------
# 4. DEFAULTS
# -----------------------------------------------------------------------------
: "${CONNECT_HEAP_OPTS:="-Xmx512M -Xms256M"}"
: "${DEBEZIUM_CONNECTOR_NAME:="debezium-postgres-lab"}"
: "${DEBEZIUM_PG_USER_PREFIX:="debezium_connector"}"
: "${DEBEZIUM_TABLE_INCLUDE_LIST:="raw.*,staging.*,analytics.*"}"

# -----------------------------------------------------------------------------
# 5. GENERATE DEBEZIUM POSTGRESQL USER 
# -----------------------------------------------------------------------------
if ! grep -q "DEBEZIUM_PG_USER" "${SECRET_FILE}"; then
    DEBEZIUM_PG_USER="${DEBEZIUM_PG_USER_PREFIX}_${STACK_ID_SHORT}"
    DEBEZIUM_PG_PASS=$(openssl rand -base64 12)

    cat >> "${SECRET_FILE}" <<EOF

# Debezium CDC PostgreSQL Credentials
DEBEZIUM_PG_USER='${DEBEZIUM_PG_USER}'
DEBEZIUM_PG_PASS='${DEBEZIUM_PG_PASS}'
EOF

    source "${SECRET_FILE}"
    echo "[SUCCESS] Debezium credentials generated."
else
    : "${DEBEZIUM_PG_USER:?DEBEZIUM_PG_USER missing.}"
    : "${DEBEZIUM_PG_PASS:?DEBEZIUM_PG_PASS missing.}"
    echo "[INFO] Debezium credentials exist."
fi

DEBEZIUM_PG_PASS_SAFE="${DEBEZIUM_PG_PASS//\'/\'\'}"

# -----------------------------------------------------------------------------
# 6. PROVISION DEBEZIUM POSTGRESQL ROLE 
# -----------------------------------------------------------------------------
echo "[INFO] Provisioning Debezium PostgreSQL role..."

"${PG_BIN_PATH}/psql" -h "${PG_RUNTIME_DIR}" -p "${PG_PORT}" -d postgres -t <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DEBEZIUM_PG_USER}') THEN
        CREATE ROLE ${DEBEZIUM_PG_USER} WITH LOGIN PASSWORD '${DEBEZIUM_PG_PASS_SAFE}' REPLICATION;
        RAISE NOTICE 'Debezium role created: %', '${DEBEZIUM_PG_USER}';
    ELSE
        RAISE NOTICE 'Debezium role exists: %', '${DEBEZIUM_PG_USER}';
    END IF;
END
\$\$;

GRANT CONNECT ON DATABASE ${PG_LAB_DB} TO ${DEBEZIUM_PG_USER};
GRANT CREATE ON DATABASE ${PG_LAB_DB} TO ${DEBEZIUM_PG_USER};
EOF

for schema in raw staging analytics; do
    "${PG_BIN_PATH}/psql" -h "${PG_RUNTIME_DIR}" -p "${PG_PORT}" -d "${PG_LAB_DB}" -t <<EOF
GRANT USAGE ON SCHEMA ${schema} TO ${DEBEZIUM_PG_USER};
GRANT SELECT ON ALL TABLES IN SCHEMA ${schema} TO ${DEBEZIUM_PG_USER};
EOF
done

echo "[SUCCESS] Debezium role provisioned."

# -----------------------------------------------------------------------------
# 7. GENERATE connect-distributed.properties
# -----------------------------------------------------------------------------
echo "[INFO] Generating Connect configuration..."

# Build SASL JAAS config string for Connect
if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
    SASL_JAAS_CONFIG="org.apache.kafka.common.security.plain.PlainLoginModule required username=${KAFKA_ADMIN_USER} password=${KAFKA_ADMIN_PASS};"
    CONNECT_SECURITY_PROTOCOL="SASL_PLAINTEXT"
else
    SASL_JAAS_CONFIG=""
    CONNECT_SECURITY_PROTOCOL="PLAINTEXT"
fi

OLD_UMASK=$(umask)
umask 077
cat > "${CONNECT_CONFIG_DIR}/connect-distributed.properties" <<EOF
# ==========================================================
# Kafka Connect Configuration — bootstrap-de-stack
# Lab: ${ENV_NAME} (${STACK_ID})
# ==========================================================

bootstrap.servers=localhost:${KAFKA_PORT}
group.id=connect-cluster-${STACK_ID_SHORT}

security.protocol=${CONNECT_SECURITY_PROTOCOL}
sasl.mechanism=PLAIN
sasl.jaas.config=${SASL_JAAS_CONFIG}

key.converter=io.confluent.connect.avro.AvroConverter
value.converter=io.confluent.connect.avro.AvroConverter
key.converter.schema.registry.url=${SCHEMA_REGISTRY_COMPAT_URL}
value.converter.schema.registry.url=${SCHEMA_REGISTRY_COMPAT_URL}

plugin.path=${CONNECT_PLUGIN_DIR}

config.storage.replication.factor=1
offset.storage.replication.factor=1
status.storage.replication.factor=1

rest.port=${CONNECT_PORT}
rest.advertised.listener=http://localhost:${CONNECT_PORT}
EOF
umask "${OLD_UMASK}"

echo "[SUCCESS] Connect configuration generated."

# -----------------------------------------------------------------------------
# 8. START KAFKA CONNECT
# -----------------------------------------------------------------------------
CONNECT_PID_FILE="${CONNECT_RUNTIME_DIR}/connect.pid"

CONNECT_RUNNING=false
if [[ -f "${CONNECT_PID_FILE}" ]]; then
    CONNECT_PID_VAL=$(cat "${CONNECT_PID_FILE}")
    if kill -0 "${CONNECT_PID_VAL}" 2>/dev/null; then
        echo "[INFO] Kafka Connect already running (PID: ${CONNECT_PID_VAL}). Skipping."
        CONNECT_RUNNING=true
    else
        rm -f "${CONNECT_PID_FILE}"
    fi
fi

if [[ "${CONNECT_RUNNING}" == "false" ]]; then
    echo "[INFO] Starting Kafka Connect..."
    export KAFKA_HEAP_OPTS="${CONNECT_HEAP_OPTS}"
    export LOG_DIR="${CONNECT_LOG_DIR}"

    nohup "${KAFKA_HOME}/bin/connect-distributed.sh" \
        "${CONNECT_CONFIG_DIR}/connect-distributed.properties" \
        > "${CONNECT_LOG_DIR}/connect-startup.log" 2>&1 &

    CONNECT_PID=$!
    echo "${CONNECT_PID}" > "${CONNECT_PID_FILE}"
    echo "[SUCCESS] Kafka Connect starting (PID: ${CONNECT_PID})."
fi

# -----------------------------------------------------------------------------
# 9. CONNECT HEALTH CHECK (30s Timeout)
# -----------------------------------------------------------------------------
echo "[INFO] Health check on Kafka Connect..."
TIMEOUT=30
CONNECT_HEALTHY=false

while [[ "${TIMEOUT}" -gt 0 ]]; do
    if curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:${CONNECT_PORT}/" \
        2>/dev/null | grep -q "200"; then
        CONNECT_HEALTHY=true
        break
    fi
    TIMEOUT=$((TIMEOUT - 1))
    sleep 1
done

if [[ "${CONNECT_HEALTHY}" == "false" ]]; then
    echo "[ERROR] Kafka Connect failed health check."
    echo "Check logs: ${CONNECT_LOG_DIR}/connect-startup.log"
    exit 1
fi

echo "[INFO] Kafka Connect healthy."

# -----------------------------------------------------------------------------
# 10. CONFIGURE DEBEZIUM CONNECTOR — AVRO SERIALIZATION
# -----------------------------------------------------------------------------
echo "[INFO] Configuring Debezium CDC connector (Avro)..."

CONNECTOR_EXISTS=false
EXISTING_CONNECTORS=$(curl -s "http://localhost:${CONNECT_PORT}/connectors" 2>/dev/null || echo "[]")

if echo "${EXISTING_CONNECTORS}" | grep -q "\"${DEBEZIUM_CONNECTOR_NAME}\""; then
    echo "[INFO] Connector '${DEBEZIUM_CONNECTOR_NAME}' exists. Updating..."
    CONNECTOR_EXISTS=true
fi

DEBEZIUM_CONNECTOR_JSON=$(cat <<INNEREOF
{
  "name": "${DEBEZIUM_CONNECTOR_NAME}",
  "config": {
    "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
    "database.hostname": "localhost",
    "database.port": "${PG_PORT}",
    "database.user": "${DEBEZIUM_PG_USER}",
    "database.password": "${DEBEZIUM_PG_PASS}",
    "database.dbname": "${PG_LAB_DB}",
    "topic.prefix": "lab_${STACK_ID_SHORT}",
    "plugin.name": "pgoutput",
    "publication.autocreate.mode": "filtered",
    "table.include.list": "${DEBEZIUM_TABLE_INCLUDE_LIST}",
    "slot.name": "debezium_${STACK_ID_SHORT}",
    "publication.name": "publication_${STACK_ID_SHORT}",
    "snapshot.mode": "initial",
    "key.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "key.converter.schema.registry.url": "${SCHEMA_REGISTRY_COMPAT_URL}",
    "value.converter.schema.registry.url": "${SCHEMA_REGISTRY_COMPAT_URL}",
    "heartbeat.interval.ms": "5000"
  }
}
INNEREOF
)

if [[ "${CONNECTOR_EXISTS}" == "true" ]]; then
    HTTP_RESPONSE=$(curl -s -w "%{http_code}" -X PUT \
        -H "Content-Type: application/json" \
        -d "${DEBEZIUM_CONNECTOR_JSON}" \
        "http://localhost:${CONNECT_PORT}/connectors/${DEBEZIUM_CONNECTOR_NAME}/config" 2>/dev/null)

    HTTP_CODE="${HTTP_RESPONSE: -3}"
    if [[ ! "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
        echo "[ERROR] Failed to update Debezium connector. HTTP ${HTTP_CODE}"
        exit 1
    fi
    echo "[SUCCESS] Debezium connector updated."
else
    HTTP_RESPONSE=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "${DEBEZIUM_CONNECTOR_JSON}" \
        "http://localhost:${CONNECT_PORT}/connectors" 2>/dev/null)

    HTTP_CODE="${HTTP_RESPONSE: -3}"
    if [[ ! "${HTTP_CODE}" =~ ^2[0-9][0-9]$ ]]; then
        echo "[ERROR] Failed to create Debezium connector. HTTP ${HTTP_CODE}"
        exit 1
    fi
    echo "[SUCCESS] Debezium connector created."
fi

# -----------------------------------------------------------------------------
# 11. CONNECTOR STATUS CHECK (30s Timeout)
# -----------------------------------------------------------------------------
echo "[INFO] Waiting for Debezium connector to reach RUNNING state..."
TIMEOUT=30
CONNECTOR_RUNNING=false

while [[ "${TIMEOUT}" -gt 0 ]]; do
    CONNECTOR_STATUS=$(curl -s \
        "http://localhost:${CONNECT_PORT}/connectors/${DEBEZIUM_CONNECTOR_NAME}/status" \
        2>/dev/null || echo '{"connector":{"state":"UNKNOWN"}}')

    STATE=$(echo "${CONNECTOR_STATUS}" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

    if [[ "${STATE}" == "RUNNING" ]]; then
        CONNECTOR_RUNNING=true
        break
    fi

    TIMEOUT=$((TIMEOUT - 1))
    sleep 1
done

if [[ "${CONNECTOR_RUNNING}" == "false" ]]; then
    echo "[ERROR] Debezium connector failed to reach RUNNING state."
    curl -s "http://localhost:${CONNECT_PORT}/connectors/${DEBEZIUM_CONNECTOR_NAME}/status" 2>/dev/null || true
    exit 1
fi

echo "[INFO] Debezium connector RUNNING."

# -----------------------------------------------------------------------------
# 12. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
export CONNECT_PORT
export CONNECT_PID_FILE
export CONNECT_RUNTIME_DIR
export CONNECT_LOG_DIR
export DEBEZIUM_CONNECTOR_NAME
export DEBEZIUM_PG_USER
export SCHEMA_REGISTRY_COMPAT_URL

echo "[SUCCESS] Script 14: Kafka Connect & Debezium CDC active."
echo "  Connect REST: http://localhost:${CONNECT_PORT}"
echo "  Connector:    ${DEBEZIUM_CONNECTOR_NAME} (RUNNING)"
echo "  Topic prefix: lab_${STACK_ID_SHORT}"
echo "  Serialization: Avro → Schema Registry"
