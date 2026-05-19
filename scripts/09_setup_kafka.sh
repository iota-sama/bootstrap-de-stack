#!/usr/bin/env bash
set -euo pipefail

# @description: Download Apache Kafka tarball, extract, and format KRaft metadata.
#              Separates Kafka binaries from topic data to prevent data loss on upgrades.
# @script: 09_setup_kafka.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run via run_setup.sh}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"
: "${STACK_ID:?STACK_ID is not set. Ensure 00_base_setup.sh ran.}"
: "${JAVA_HOME:?JAVA_HOME is not set. Ensure 08_setup_java.sh ran.}"

# -----------------------------------------------------------------------------
# 2. DEFAULTS & CONFIGURATION
# -----------------------------------------------------------------------------
: "${KAFKA_VERSION:="4.0.2"}"
: "${KAFKA_SCALA_VERSION:="2.13"}"
: "${KAFKA_HOME:="${LAB_HOME}/engine/kafka"}"
: "${KAFKA_DATA_DIR:="${LAB_HOME}/data/kafka"}"
: "${KAFKA_LOG_DIR:="${LAB_HOME}/logs/kafka"}"
: "${KAFKA_RUNTIME_DIR:="${LAB_HOME}/runtime/kafka"}"
: "${KAFKA_CONFIG_DIR:="${LAB_HOME}/configs/kafka"}"
: "${CACHE_DIR:="${BOOTSTRAP_DIR}/cache"}"

KAFKA_TARBALL="kafka_${KAFKA_SCALA_VERSION}-${KAFKA_VERSION}.tgz"
KAFKA_DOWNLOAD_URL="https://downloads.apache.org/kafka/${KAFKA_VERSION}/${KAFKA_TARBALL}"

export KAFKA_HOME KAFKA_DATA_DIR KAFKA_LOG_DIR KAFKA_RUNTIME_DIR KAFKA_CONFIG_DIR KAFKA_VERSION KAFKA_SCALA_VERSION

# -----------------------------------------------------------------------------
# 3. CREATE DIRECTORY STRUCTURE
# -----------------------------------------------------------------------------
echo "[PROGRESS] Starting Kafka ${KAFKA_VERSION} setup (Scala ${KAFKA_SCALA_VERSION})..."

mkdir -p "${KAFKA_HOME}"
mkdir -p "${KAFKA_DATA_DIR}/logs"
mkdir -p "${KAFKA_LOG_DIR}"
mkdir -p "${KAFKA_RUNTIME_DIR}"
mkdir -p "${KAFKA_CONFIG_DIR}"
mkdir -p "${CACHE_DIR}"

# -----------------------------------------------------------------------------
# 4. DOWNLOAD & EXTRACT KAFKA
# -----------------------------------------------------------------------------
KAFKA_VERSION_FILE="${KAFKA_HOME}/.kafka_version"

if [[ -f "${KAFKA_VERSION_FILE}" ]] && [[ "$(cat "${KAFKA_VERSION_FILE}")" == "${KAFKA_VERSION}" ]]; then
    echo "[INFO] Kafka ${KAFKA_VERSION} already extracted. Skipping download."
else
    if [[ -f "${KAFKA_VERSION_FILE}" ]]; then
        EXISTING_VER=$(cat "${KAFKA_VERSION_FILE}")
        echo "[WARN] Kafka version changed from ${EXISTING_VER} to ${KAFKA_VERSION}."
        echo "[WARN] Removing old Kafka binaries. Topic data at ${KAFKA_DATA_DIR} is preserved."
        rm -rf "${KAFKA_HOME}"/*
    fi

    if [[ ! -f "${CACHE_DIR}/${KAFKA_TARBALL}" ]]; then
        echo "[INFO] Downloading Kafka ${KAFKA_VERSION} from Apache..."
        if ! wget -q --show-progress -P "${CACHE_DIR}" "${KAFKA_DOWNLOAD_URL}" 2>&1; then
            echo "[ERROR] Failed to download Kafka from ${KAFKA_DOWNLOAD_URL}"
            exit 1
        fi
        echo "[SUCCESS] Kafka tarball downloaded."
    else
        echo "[INFO] Kafka tarball found in cache. Skipping download."
    fi

    TEMP_EXTRACT="${KAFKA_HOME}.tmp"
    rm -rf "${TEMP_EXTRACT}"
    mkdir -p "${TEMP_EXTRACT}"

    echo "[INFO] Extracting Kafka ${KAFKA_VERSION}..."
    tar xzf "${CACHE_DIR}/${KAFKA_TARBALL}" -C "${TEMP_EXTRACT}" --strip-components=1

    mv "${TEMP_EXTRACT}"/* "${KAFKA_HOME}/" 2>/dev/null || true
    rm -rf "${TEMP_EXTRACT}"

    echo "${KAFKA_VERSION}" > "${KAFKA_VERSION_FILE}"
    echo "[SUCCESS] Kafka ${KAFKA_VERSION} extracted to ${KAFKA_HOME}"
fi

# Set binary path for downstream scripts
KAFKA_BIN_PATH="${KAFKA_HOME}/bin"
export KAFKA_BIN_PATH

# -----------------------------------------------------------------------------
# 5. GENERATE MINIMAL server.properties FOR KRaft METADATA FORMATTING
# -----------------------------------------------------------------------------
mkdir -p "${KAFKA_CONFIG_DIR}"
cat > "${KAFKA_CONFIG_DIR}/server.properties" <<EOF
process.roles=broker,controller
node.id=1
controller.quorum.voters=1@localhost:1
listeners=BROKER://localhost:1,CONTROLLER://localhost:2
controller.listener.names=CONTROLLER
inter.broker.listener.name=BROKER
advertised.listeners=BROKER://localhost:1
listener.security.protocol.map=BROKER:PLAINTEXT,CONTROLLER:PLAINTEXT
log.dirs=${KAFKA_DATA_DIR}/logs
EOF

# -----------------------------------------------------------------------------
# 6. GENERATE KAFKA CLUSTER ID (Idempotent)
# -----------------------------------------------------------------------------
KAFKA_META_FILE="${KAFKA_DATA_DIR}/logs/meta.properties"

if [[ -z "${KAFKA_CLUSTER_ID:-}" ]]; then
    if [[ -f "${KAFKA_META_FILE}" ]]; then
        KAFKA_CLUSTER_ID=$(grep "cluster.id" "${KAFKA_META_FILE}" 2>/dev/null | cut -d'=' -f2)
        if [[ -n "${KAFKA_CLUSTER_ID}" ]]; then
            echo "[INFO] Reusing existing Kafka cluster ID: ${KAFKA_CLUSTER_ID}"
        else
            echo "[WARN] Metadata file exists but cluster ID is missing or empty. Regenerating..."
            KAFKA_CLUSTER_ID=$(uuidgen)
            echo "[INFO] Generated new Kafka cluster ID: ${KAFKA_CLUSTER_ID}"
            # Force reformat by removing the broken metadata file
            rm -f "${KAFKA_META_FILE}"
        fi
    else
        KAFKA_CLUSTER_ID=$(uuidgen)
        echo "[INFO] Generated new Kafka cluster ID: ${KAFKA_CLUSTER_ID}"
    fi
    export KAFKA_CLUSTER_ID
fi


# -----------------------------------------------------------------------------
# 7. FORMAT KRaft METADATA
# -----------------------------------------------------------------------------
if [[ -f "${KAFKA_META_FILE}" ]]; then
    echo "[INFO] KRaft metadata already exists. Skipping format."
else
    echo "[INFO] Formatting KRaft metadata (cluster ID: ${KAFKA_CLUSTER_ID})..."
    "${KAFKA_BIN_PATH}/kafka-storage.sh" format \
        --cluster-id "${KAFKA_CLUSTER_ID}" \
        --config "${KAFKA_CONFIG_DIR}/server.properties" \
        --ignore-formatted 2>&1 || {
        echo "[ERROR] KRaft metadata formatting failed."
        exit 1
    }
    echo "[SUCCESS] KRaft metadata formatted."
fi

# -----------------------------------------------------------------------------
# 8. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
export KAFKA_BIN_PATH
export KAFKA_CLUSTER_ID
export KAFKA_HOME
export KAFKA_DATA_DIR

echo "[SUCCESS] Script 09: Kafka ${KAFKA_VERSION} engine is ready."
echo "  Engine dir: ${KAFKA_HOME}"
echo "  Data dir:   ${KAFKA_DATA_DIR}"
echo "  Bin path:   ${KAFKA_BIN_PATH}"
echo "  Cluster:    ${KAFKA_CLUSTER_ID}"
