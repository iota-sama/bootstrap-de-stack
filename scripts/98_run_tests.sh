#!/usr/bin/env bash
set -euo pipefail

# @description: Integration tests for CDC pipeline validation.
#              Tests run against assembled lab, logs results, does NOT block delivery.
# @script: 98_run_tests.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set.}"
: "${PG_PORT:?PG_PORT not set.}"
: "${PG_LAB_DB:?PG_LAB_DB not set.}"
: "${PG_RUNTIME_DIR:?PG_RUNTIME_DIR not set.}"
: "${PG_BIN_PATH:?PG_BIN_PATH not set.}"
: "${KAFKA_PORT:?KAFKA_PORT not set.}"
: "${KAFKA_BIN_PATH:?KAFKA_BIN_PATH not set.}"
: "${CONNECT_PORT:?CONNECT_PORT not set.}"
: "${DEBEZIUM_CONNECTOR_NAME:?DEBEZIUM_CONNECTOR_NAME not set.}"
: "${STACK_ID:?STACK_ID not set.}"
: "${SECRET_FILE:="${LAB_HOME}/secrets/generated.env"}"
: "${KAFKA_ENABLE_SASL:?KAFKA_ENABLE_SASL is not set.}"

source "${SECRET_FILE}"

if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
    : "${KAFKA_ADMIN_USER:?KAFKA_ADMIN_USER not set. Check secrets file.}"
    : "${KAFKA_ADMIN_PASS:?KAFKA_ADMIN_PASS not set. Check secrets file.}"
fi

STACK_ID_SHORT="${STACK_ID:0:8}"
TEST_LOG="${LAB_HOME}/logs/test_results.log"
TEST_SCHEMA="_test_cdc_${STACK_ID_SHORT}"
TEST_TABLE="cdc_validation"
PASSED=0
FAILED=0

# -----------------------------------------------------------------------------
# 2. INITIALIZE TEST LOG
# -----------------------------------------------------------------------------
mkdir -p "$(dirname "${TEST_LOG}")"
cat > "${TEST_LOG}" <<EOF
==================================================
CDC Integration Test Results
Lab: ${ENV_NAME} (${STACK_ID})
Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
==================================================

EOF

log_test() {
    local status="$1"
    local message="$2"
    echo "[${status}] ${message}" | tee -a "${TEST_LOG}"
    if [[ "${status}" == "PASS" ]]; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
}

# Helper: build SASL config for Kafka CLI if SASL is enabled
build_kafka_config() {
    if [[ "${KAFKA_ENABLE_SASL}" == "true" ]]; then
        echo "sasl.mechanism=PLAIN"
        echo "security.protocol=SASL_PLAINTEXT"
        echo "sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username=${KAFKA_ADMIN_USER} password=${KAFKA_ADMIN_PASS};"
    fi
}

# -----------------------------------------------------------------------------
# 3. TEST: Connector Status
# -----------------------------------------------------------------------------
echo "[TEST] Checking Debezium connector status..."

CONNECTOR_STATUS=$(curl -s \
    "http://localhost:${CONNECT_PORT}/connectors/${DEBEZIUM_CONNECTOR_NAME}/status" \
    2>/dev/null || echo '{"connector":{"state":"UNKNOWN"}}')

STATE=$(echo "${CONNECTOR_STATUS}" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ "${STATE}" == "RUNNING" ]]; then
    log_test "PASS" "Debezium connector is RUNNING"
else
    log_test "FAIL" "Debezium connector state: ${STATE}"
fi

# -----------------------------------------------------------------------------
# 4. TEST: End-to-End CDC Pipeline
# -----------------------------------------------------------------------------
echo "[TEST] Testing CDC pipeline end-to-end..."

"${PG_BIN_PATH}/psql" -h "${PG_RUNTIME_DIR}" -p "${PG_PORT}" -d "${PG_LAB_DB}" -t <<EOF
CREATE SCHEMA IF NOT EXISTS ${TEST_SCHEMA};
CREATE TABLE IF NOT EXISTS ${TEST_SCHEMA}.${TEST_TABLE} (
    id SERIAL PRIMARY KEY,
    test_value TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);
EOF

TEST_VALUE="cdc-test-$(date +%s)"
"${PG_BIN_PATH}/psql" -h "${PG_RUNTIME_DIR}" -p "${PG_PORT}" -d "${PG_LAB_DB}" -t <<EOF
INSERT INTO ${TEST_SCHEMA}.${TEST_TABLE} (test_value) VALUES ('${TEST_VALUE}');
EOF

sleep 3

TOPIC_NAME="lab_${STACK_ID_SHORT}.${TEST_SCHEMA}.${TEST_TABLE}"

KAFKA_CONFIG=$(build_kafka_config)
if [[ -n "${KAFKA_CONFIG}" ]]; then
    TOPIC_CHECK=$("${KAFKA_BIN_PATH}/kafka-topics.sh" \
        --bootstrap-server "localhost:${KAFKA_PORT}" \
        --command-config <(echo "${KAFKA_CONFIG}") \
        --list 2>/dev/null | grep "${TOPIC_NAME}" || true)
else
    TOPIC_CHECK=$("${KAFKA_BIN_PATH}/kafka-topics.sh" \
        --bootstrap-server "localhost:${KAFKA_PORT}" \
        --list 2>/dev/null | grep "${TOPIC_NAME}" || true)
fi

if [[ -n "${TOPIC_CHECK}" ]]; then
    log_test "PASS" "CDC topic created: ${TOPIC_NAME}"
else
    log_test "FAIL" "CDC topic not found: ${TOPIC_NAME}"
fi

# -----------------------------------------------------------------------------
# 5. CLEANUP
# -----------------------------------------------------------------------------
echo "[TEST] Cleaning up test resources..."

"${PG_BIN_PATH}/psql" -h "${PG_RUNTIME_DIR}" -p "${PG_PORT}" -d "${PG_LAB_DB}" -t <<EOF
DROP TABLE IF EXISTS ${TEST_SCHEMA}.${TEST_TABLE} CASCADE;
DROP SCHEMA IF EXISTS ${TEST_SCHEMA} CASCADE;
EOF

echo "[TEST] Test schema cleaned."

# -----------------------------------------------------------------------------
# 6. SUMMARY
# -----------------------------------------------------------------------------
TOTAL=$((PASSED + FAILED))
cat >> "${TEST_LOG}" <<EOF

==================================================
Results: ${PASSED}/${TOTAL} passed, ${FAILED}/${TOTAL} failed
==================================================
EOF

echo "[TEST] Results written to: ${TEST_LOG}"
echo "  Passed: ${PASSED}"
echo "  Failed: ${FAILED}"

if [[ "${FAILED}" -gt 0 ]]; then
    echo "[WARN] Some integration tests failed. See ${TEST_LOG}"
fi