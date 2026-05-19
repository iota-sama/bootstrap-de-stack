#!/usr/bin/env bash
set -euo pipefail

# @description: Download and extract Apicurio Schema Registry runner JAR.
# @script: 11_setup_schema_registry.sh
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
: "${SCHEMA_REGISTRY_VERSION:="3.2.4"}"
: "${SCHEMA_REGISTRY_HOME:="${LAB_HOME}/engine/schema-registry"}"
: "${SCHEMA_REGISTRY_LOG_DIR:="${LAB_HOME}/logs/schema-registry"}"
: "${SCHEMA_REGISTRY_RUNTIME_DIR:="${LAB_HOME}/runtime/schema-registry"}"

: "${CACHE_DIR:="${BOOTSTRAP_DIR}/cache"}"
SCHEMA_REGISTRY_ARCHIVE="apicurio-registry-app-${SCHEMA_REGISTRY_VERSION}-all.tar.gz"
SCHEMA_REGISTRY_DOWNLOAD_URL="https://github.com/Apicurio/apicurio-registry/releases/download/${SCHEMA_REGISTRY_VERSION}/${SCHEMA_REGISTRY_ARCHIVE}"

export SCHEMA_REGISTRY_HOME SCHEMA_REGISTRY_LOG_DIR SCHEMA_REGISTRY_RUNTIME_DIR SCHEMA_REGISTRY_VERSION

# -----------------------------------------------------------------------------
# 3. CREATE DIRECTORY STRUCTURE
# -----------------------------------------------------------------------------
echo "[PROGRESS] Starting Schema Registry ${SCHEMA_REGISTRY_VERSION} setup..."

mkdir -p "${SCHEMA_REGISTRY_HOME}"
mkdir -p "${SCHEMA_REGISTRY_LOG_DIR}"
mkdir -p "${SCHEMA_REGISTRY_RUNTIME_DIR}"
mkdir -p "${CACHE_DIR}"

# -----------------------------------------------------------------------------
# 4. DOWNLOAD & EXTRACT APICURIO (Idempotent)
# -----------------------------------------------------------------------------
SCHEMA_REGISTRY_VERSION_FILE="${SCHEMA_REGISTRY_HOME}/.schema_registry_version"

if [[ -f "${SCHEMA_REGISTRY_VERSION_FILE}" ]] && [[ "$(cat "${SCHEMA_REGISTRY_VERSION_FILE}")" == "${SCHEMA_REGISTRY_VERSION}" ]]; then
    echo "[INFO] Apicurio ${SCHEMA_REGISTRY_VERSION} already extracted. Skipping download."
else
    if [[ -f "${SCHEMA_REGISTRY_VERSION_FILE}" ]]; then
        echo "[INFO] Schema Registry version changed. Re-extracting..."
        rm -rf "${SCHEMA_REGISTRY_HOME}"/*
    fi

    if [[ ! -f "${CACHE_DIR}/${SCHEMA_REGISTRY_ARCHIVE}" ]]; then
        echo "[INFO] Downloading Apicurio Registry ${SCHEMA_REGISTRY_VERSION}..."
        if ! wget -q --show-progress -P "${CACHE_DIR}" "${SCHEMA_REGISTRY_DOWNLOAD_URL}" 2>&1; then
            echo "[ERROR] Failed to download Apicurio from ${SCHEMA_REGISTRY_DOWNLOAD_URL}"
            exit 1
        fi
        echo "[SUCCESS] Apicurio archive downloaded."
    else
        echo "[INFO] Apicurio archive found in cache. Skipping download."
    fi

    echo "[INFO] Extracting Apicurio Registry..."
    rm -rf "${SCHEMA_REGISTRY_HOME}"/*
    tar xzf "${CACHE_DIR}/${SCHEMA_REGISTRY_ARCHIVE}" -C "${SCHEMA_REGISTRY_HOME}"
    
    echo "${SCHEMA_REGISTRY_VERSION}" > "${SCHEMA_REGISTRY_VERSION_FILE}"
    echo "[SUCCESS] Apicurio Registry ${SCHEMA_REGISTRY_VERSION} extracted."
fi

# -----------------------------------------------------------------------------
# 5. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
echo "[SUCCESS] Script 11: Schema Registry engine ready."
echo "  Version: ${SCHEMA_REGISTRY_VERSION}"
echo "  Home:    ${SCHEMA_REGISTRY_HOME}"
