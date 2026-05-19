#!/usr/bin/env bash
set -euo pipefail

# @description: Seed Kafka and Schema Registry connections in Airflow.
# @script: 15_seed_airflow_kafka.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set.}"
: "${AIRFLOW_VENV:?AIRFLOW_VENV not set.}"
: "${AIRFLOW_HOME:?AIRFLOW_HOME not set.}"
: "${KAFKA_PORT:?KAFKA_PORT not set.}"
: "${SCHEMA_REGISTRY_PORT:?SCHEMA_REGISTRY_PORT not set.}"
: "${AIRFLOW_DB_USER:?AIRFLOW_DB_USER not set.}"
: "${AIRFLOW_DB_PASS:?AIRFLOW_DB_PASS not set.}"
: "${AIRFLOW_DB_NAME:?AIRFLOW_DB_NAME not set.}"
: "${PG_PORT:?PG_PORT not set.}"
: "${SECRET_FILE:="${LAB_HOME}/secrets/generated.env"}"
: "${SCHEMA_REGISTRY_COMPAT_URL:?SCHEMA_REGISTRY_COMPAT_URL not set.}"
: "${KAFKA_ENABLE_SASL:?KAFKA_ENABLE_SASL not set.}"

source "${SECRET_FILE}"

if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
    : "${KAFKA_ADMIN_USER:?KAFKA_ADMIN_USER not set. Check secrets file.}"
    : "${KAFKA_ADMIN_PASS:?KAFKA_ADMIN_PASS not set. Check secrets file.}"
fi

# -----------------------------------------------------------------------------
# 2. SETUP AIRFLOW ENVIRONMENT
# -----------------------------------------------------------------------------
export AIRFLOW_HOME="${AIRFLOW_HOME}"
export AIRFLOW__DATABASE__SQL_ALCHEMY_CONN="postgresql://${AIRFLOW_DB_USER}:${AIRFLOW_DB_PASS}@localhost:${PG_PORT}/${AIRFLOW_DB_NAME}"

# -----------------------------------------------------------------------------
# 3. SEED KAFKA CONNECTION
# -----------------------------------------------------------------------------
echo "[INFO] Seeding Airflow Kafka connection..."

: "${KAFKA_CONN_ID:="lab_kafka"}"

if "${AIRFLOW_VENV}/bin/airflow" connections list 2>/dev/null | grep -q "${KAFKA_CONN_ID}"; then
    echo "[INFO] Connection '${KAFKA_CONN_ID}' exists. Updating..."
    "${AIRFLOW_VENV}/bin/airflow" connections delete "${KAFKA_CONN_ID}" 2>/dev/null || true
fi

if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
    "${AIRFLOW_VENV}/bin/airflow" connections add "${KAFKA_CONN_ID}" \
        --conn-type "kafka" \
        --conn-host "localhost" \
        --conn-port "${KAFKA_PORT}" \
        --conn-extra "{\"security_protocol\": \"SASL_PLAINTEXT\", \"sasl_mechanism\": \"PLAIN\", \"sasl_plain_username\": \"${KAFKA_ADMIN_USER}\", \"sasl_plain_password\": \"${KAFKA_ADMIN_PASS}\"}"
else
    "${AIRFLOW_VENV}/bin/airflow" connections add "${KAFKA_CONN_ID}" \
        --conn-type "kafka" \
        --conn-host "localhost" \
        --conn-port "${KAFKA_PORT}" \
        --conn-extra "{\"security_protocol\": \"PLAINTEXT\"}"
fi

echo "[SUCCESS] Kafka connection '${KAFKA_CONN_ID}' seeded."

# -----------------------------------------------------------------------------
# 4. SEED SCHEMA REGISTRY CONNECTION (Idempotent)
# -----------------------------------------------------------------------------
echo "[INFO] Seeding Airflow Schema Registry connection..."

: "${SCHEMA_REGISTRY_CONN_ID:="lab_schema_registry"}"

if "${AIRFLOW_VENV}/bin/airflow" connections list 2>/dev/null | grep -q "${SCHEMA_REGISTRY_CONN_ID}"; then
    echo "[INFO] Connection '${SCHEMA_REGISTRY_CONN_ID}' exists. Updating..."
    "${AIRFLOW_VENV}/bin/airflow" connections delete "${SCHEMA_REGISTRY_CONN_ID}" 2>/dev/null || true
fi

"${AIRFLOW_VENV}/bin/airflow" connections add "${SCHEMA_REGISTRY_CONN_ID}" \
    --conn-type "http" \
    --conn-host "localhost" \
    --conn-port "${SCHEMA_REGISTRY_PORT}"

echo "[SUCCESS] Schema Registry connection '${SCHEMA_REGISTRY_CONN_ID}' seeded."

# -----------------------------------------------------------------------------
# 5. EXPORT
# -----------------------------------------------------------------------------
export KAFKA_CONN_ID
export SCHEMA_REGISTRY_CONN_ID

echo "[SUCCESS] Script 15: Airflow streaming connections ready."
echo "  Kafka:          ${KAFKA_CONN_ID} → localhost:${KAFKA_PORT}"
echo "  Schema Registry: ${SCHEMA_REGISTRY_CONN_ID}"
echo "    Native API:    http://localhost:${SCHEMA_REGISTRY_PORT}"
echo "    Confluent API: ${SCHEMA_REGISTRY_COMPAT_URL}"
echo "  Use the appropriate endpoint in your DAG code."