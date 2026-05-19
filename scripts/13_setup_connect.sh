#!/usr/bin/env bash
set -euo pipefail

# @description: Install Debezium PostgreSQL connector and Avro converter plugins.
# @script: 13_setup_connect.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set.}"
: "${STACK_ID:?STACK_ID is not set.}"
: "${KAFKA_HOME:?Ensure 09_setup_kafka.sh ran.}"
: "${KAFKA_VERSION:?Ensure 09_setup_kafka.sh ran.}"

# -----------------------------------------------------------------------------
# 2. DEFAULTS & CONFIGURATION
# -----------------------------------------------------------------------------
: "${DEBEZIUM_VERSION:="3.4.3.Final"}"
: "${CONNECT_LOG_DIR:="${LAB_HOME}/logs/connect"}"
: "${CONNECT_RUNTIME_DIR:="${LAB_HOME}/runtime/connect"}"
: "${CONNECT_CONFIG_DIR:="${LAB_HOME}/configs/connect"}"

CONNECT_PLUGIN_DIR="${KAFKA_HOME}/plugins"
DEBEZIUM_PG_PLUGIN_DIR="${CONNECT_PLUGIN_DIR}/debezium-postgres"
AVRO_CONVERTER_DIR="${CONNECT_PLUGIN_DIR}/avro-converter"

: "${CACHE_DIR:="${BOOTSTRAP_DIR}/cache"}"

# Debezium PostgreSQL connector
DEBEZIUM_ARCHIVE="debezium-connector-postgres-${DEBEZIUM_VERSION}.zip"
DEBEZIUM_DOWNLOAD_URL="https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/${DEBEZIUM_VERSION}/${DEBEZIUM_ARCHIVE}"

# Avro converter (Confluent, Apache 2.0 licensed client library)
: "${AVRO_CONVERTER_VERSION:="8.0.5"}"
AVRO_CONVERTER_JAR="kafka-connect-avro-converter-${AVRO_CONVERTER_VERSION}.jar"
AVRO_DATA_JAR="kafka-connect-avro-data-${AVRO_CONVERTER_VERSION}.jar"
AVRO_CONVERTER_BASE_URL="https://packages.confluent.io/maven/io/confluent/kafka-connect-avro-converter/${AVRO_CONVERTER_VERSION}"

export CONNECT_LOG_DIR CONNECT_RUNTIME_DIR CONNECT_CONFIG_DIR CONNECT_PLUGIN_DIR DEBEZIUM_VERSION

# -----------------------------------------------------------------------------
# 3. CREATE DIRECTORY STRUCTURE
# -----------------------------------------------------------------------------
echo "[PROGRESS] Starting Kafka Connect & plugin setup..."

mkdir -p "${CONNECT_LOG_DIR}"
mkdir -p "${CONNECT_RUNTIME_DIR}"
mkdir -p "${CONNECT_CONFIG_DIR}"
mkdir -p "${DEBEZIUM_PG_PLUGIN_DIR}"
mkdir -p "${AVRO_CONVERTER_DIR}"
mkdir -p "${CACHE_DIR}"

# -----------------------------------------------------------------------------
# 4. DOWNLOAD DEBEZIUM POSTGRES CONNECTOR
# -----------------------------------------------------------------------------
DEBEZIUM_VERSION_FILE="${DEBEZIUM_PG_PLUGIN_DIR}/.version"

if [[ -f "${DEBEZIUM_VERSION_FILE}" ]] && [[ "$(cat "${DEBEZIUM_VERSION_FILE}")" == "${DEBEZIUM_VERSION}" ]]; then
    echo "[INFO] Debezium PostgreSQL connector ${DEBEZIUM_VERSION} already installed."
else
    if [[ -f "${DEBEZIUM_VERSION_FILE}" ]]; then
        echo "[INFO] Debezium version changed. Reinstalling..."
        rm -rf "${DEBEZIUM_PG_PLUGIN_DIR}"/*
    fi

    if [[ ! -f "${CACHE_DIR}/${DEBEZIUM_ARCHIVE}" ]]; then
        echo "[INFO] Downloading Debezium PostgreSQL connector ${DEBEZIUM_VERSION}..."
        if ! wget -q --show-progress -P "${CACHE_DIR}" "${DEBEZIUM_DOWNLOAD_URL}" 2>&1; then
            echo "[ERROR] Failed to download Debezium connector from ${DEBEZIUM_DOWNLOAD_URL}"
            exit 1
        fi
        echo "[SUCCESS] Debezium connector downloaded."
    else
        echo "[INFO] Debezium connector found in cache. Skipping download."
    fi

    echo "[INFO] Extracting Debezium connector..."
    unzip -o "${CACHE_DIR}/${DEBEZIUM_ARCHIVE}" -d "${DEBEZIUM_PG_PLUGIN_DIR}" > /dev/null 2>&1

    echo "${DEBEZIUM_VERSION}" > "${DEBEZIUM_VERSION_FILE}"
    echo "[SUCCESS] Debezium PostgreSQL connector ${DEBEZIUM_VERSION} installed."
fi

# -----------------------------------------------------------------------------
# 5. DOWNLOAD AVRO CONVERTER
# -----------------------------------------------------------------------------
AVRO_CONVERTER_VERSION_FILE="${AVRO_CONVERTER_DIR}/.version"

if [[ -f "${AVRO_CONVERTER_VERSION_FILE}" ]] && [[ "$(cat "${AVRO_CONVERTER_VERSION_FILE}")" == "${AVRO_CONVERTER_VERSION}" ]]; then
    echo "[INFO] Avro converter ${AVRO_CONVERTER_VERSION} already installed."
else
    if [[ -f "${AVRO_CONVERTER_VERSION_FILE}" ]]; then
        echo "[INFO] Avro converter version changed. Reinstalling..."
        rm -rf "${AVRO_CONVERTER_DIR}"/*
    fi

    echo "[INFO] Downloading Avro converter ${AVRO_CONVERTER_VERSION}..."

    for JAR in "${AVRO_CONVERTER_JAR}" "${AVRO_DATA_JAR}"; do
        if [[ ! -f "${CACHE_DIR}/${JAR}" ]]; then
            if ! wget -q --show-progress -P "${CACHE_DIR}" "${AVRO_CONVERTER_BASE_URL}/${JAR}" 2>&1; then
                echo "[ERROR] Failed to download ${JAR}"
                exit 1
            fi
        fi
        cp "${CACHE_DIR}/${JAR}" "${AVRO_CONVERTER_DIR}/"
    done

    echo "${AVRO_CONVERTER_VERSION}" > "${AVRO_CONVERTER_VERSION_FILE}"
    echo "[SUCCESS] Avro converter ${AVRO_CONVERTER_VERSION} installed."
fi

# -----------------------------------------------------------------------------
# 6. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
export DEBEZIUM_PG_PLUGIN_DIR
export AVRO_CONVERTER_DIR
export CONNECT_PLUGIN_DIR
export DEBEZIUM_VERSION

echo "[SUCCESS] Script 13: Kafka Connect plugins ready."
echo "  Debezium: ${DEBEZIUM_PG_PLUGIN_DIR} (v${DEBEZIUM_VERSION})"
echo "  Avro:     ${AVRO_CONVERTER_DIR} (v${AVRO_CONVERTER_VERSION})"