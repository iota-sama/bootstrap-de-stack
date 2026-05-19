#!/usr/bin/env bash
set -euo pipefail

# @description: Download and install Eclipse Temurin JDK per lab via Adoptium API v3.
#              Uses the Assets API to fetch the latest JDK release with checksum.
# @script: 08_setup_java.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run via run_setup.sh}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"
: "${STACK_ID:?STACK_ID is not set. Ensure 00_base_setup.sh ran.}"

# -----------------------------------------------------------------------------
# 2. DEFAULTS & CONFIGURATION
# -----------------------------------------------------------------------------
: "${JAVA_MAJOR:="17"}"
: "${JAVA_HOME:="${LAB_HOME}/engine/java"}"
: "${CACHE_DIR:="${BOOTSTRAP_DIR}/cache"}"
: "${ASSETS_API:="https://api.adoptium.net/v3/assets/latest/${JAVA_MAJOR}/hotspot"}"

export JAVA_HOME JAVA_MAJOR

# -----------------------------------------------------------------------------
# 3. CREATE DIRECTORIES
# -----------------------------------------------------------------------------
echo "[PROGRESS] Starting Java ${JAVA_MAJOR} setup via Adoptium API..."

mkdir -p "${JAVA_HOME}"
mkdir -p "${CACHE_DIR}"

# -----------------------------------------------------------------------------
# 4. IDEMPOTENCY CHECK
# -----------------------------------------------------------------------------
JAVA_BIN="${JAVA_HOME}/bin/java"

if [[ -x "${JAVA_BIN}" ]]; then
    EXISTING_VERSION=$("${JAVA_BIN}" -version 2>&1 | head -1 || true)
    JAVA_MAJOR_EXISTING=$("${JAVA_BIN}" -version 2>&1 | head -1 | awk -F '"' '{print $2}' | cut -d'.' -f1)

    if [[ "${JAVA_MAJOR_EXISTING}" == "${JAVA_MAJOR}" ]]; then
        echo "[INFO] Java ${JAVA_MAJOR} already installed at ${JAVA_HOME}."
        echo "[INFO] Version: ${EXISTING_VERSION}"
        export JAVA_HOME
        echo "[SUCCESS] Script 08: Java ${JAVA_MAJOR} is ready (existing)."
        return 0 2>/dev/null || exit 0
    else
        echo "[INFO] Existing Java is major version ${JAVA_MAJOR_EXISTING}, need ${JAVA_MAJOR}. Reinstalling..."
        rm -rf "${JAVA_HOME}"/*
    fi
fi

# -----------------------------------------------------------------------------
# 5. FETCH RELEASE METADATA VIA ASSETS API
# -----------------------------------------------------------------------------
echo "[INFO] Fetching latest JDK ${JAVA_MAJOR} release metadata..."

ASSETS_JSON=$(curl -sS "${ASSETS_API}" 2>/dev/null)

if [[ -z "${ASSETS_JSON}" ]]; then
    echo "[ERROR] Empty response from Adoptium API: ${ASSETS_API}"
    exit 1
fi

# Parse Adoptium Assets API response for the Linux x64 JDK binary
RELEASE_NAME=$(echo "${ASSETS_JSON}" | jq -r '.[0].release_name')

BINARY_PACKAGE=$(echo "${ASSETS_JSON}" | jq -r '
    .[].binary |
    select(
        .os == "linux" and
        .architecture == "x64" and
        .image_type == "jdk"
    )
')

if [[ -z "${BINARY_PACKAGE}" ]]; then
    echo "[ERROR] No matching Linux x64 JDK binary found in Adoptium API response."
    echo "[ERROR] Check JAVA_MAJOR (${JAVA_MAJOR}), OS (linux), architecture (x64)."
    exit 1
fi

DOWNLOAD_URL=$(echo "${BINARY_PACKAGE}" | jq -r '.package.link')
CHECKSUM=$(echo "${BINARY_PACKAGE}" | jq -r '.package.checksum')

if [[ -z "${DOWNLOAD_URL}" ]] || [[ -z "${CHECKSUM}" ]]; then
    echo "[ERROR] Could not parse download URL or checksum from API response."
    exit 1
fi

echo "[INFO] Release: ${RELEASE_NAME}"
echo "[INFO] Download URL: ${DOWNLOAD_URL}"

# -----------------------------------------------------------------------------
# 6. DOWNLOAD JDK
# -----------------------------------------------------------------------------
FILENAME=$(basename "${DOWNLOAD_URL}")
DOWNLOAD_PATH="${CACHE_DIR}/${FILENAME}"

if [[ -f "${DOWNLOAD_PATH}" ]]; then
    echo "[INFO] JDK archive already cached: ${FILENAME}"
else
    echo "[INFO] Downloading JDK..."
    if ! curl -L --retry 3 -o "${DOWNLOAD_PATH}" "${DOWNLOAD_URL}" 2>&1; then
        echo "[ERROR] Failed to download JDK from ${DOWNLOAD_URL}"
        rm -f "${DOWNLOAD_PATH}"
        exit 1
    fi
    echo "[SUCCESS] Downloaded: ${FILENAME}"
fi

# -----------------------------------------------------------------------------
# 7. SHA-256 CHECKSUM VERIFICATION
# -----------------------------------------------------------------------------
echo "[INFO] Verifying SHA-256 checksum..."

ACTUAL_HASH=$(sha256sum "${DOWNLOAD_PATH}" | awk '{print $1}')

if [[ "${ACTUAL_HASH}" != "${CHECKSUM}" ]]; then
    echo "[ERROR] SHA-256 checksum verification FAILED!"
    echo "  Expected: ${CHECKSUM}"
    echo "  Actual:   ${ACTUAL_HASH}"
    rm -f "${DOWNLOAD_PATH}"
    exit 1
fi

echo "[INFO] Checksum verified."

# -----------------------------------------------------------------------------
# 8. EXTRACT JDK
# -----------------------------------------------------------------------------
echo "[INFO] Extracting JDK to ${JAVA_HOME}..."

rm -rf "${JAVA_HOME}"/*
mkdir -p "${JAVA_HOME}"

if ! tar xzf "${DOWNLOAD_PATH}" -C "${JAVA_HOME}" --strip-components=1 2>&1; then
    echo "[ERROR] Extraction failed."
    rm -rf "${JAVA_HOME}"/*
    exit 1
fi

echo "[SUCCESS] JDK extracted."

# -----------------------------------------------------------------------------
# 9. VALIDATE EXTRACTION & SET JAVA_HOME
# -----------------------------------------------------------------------------
if [[ ! -x "${JAVA_BIN}" ]]; then
    echo "[ERROR] java binary not found at: ${JAVA_BIN}"
    ls -la "${JAVA_HOME}/" 2>/dev/null || true
    exit 1
fi

export JAVA_HOME

# -----------------------------------------------------------------------------
# 10. VALIDATE VERSION
# -----------------------------------------------------------------------------
JAVA_VERSION_OUTPUT=$("${JAVA_BIN}" -version 2>&1 | head -1)
echo "[INFO] Installed Java version: ${JAVA_VERSION_OUTPUT}"

JAVA_MAJOR_INSTALLED=$("${JAVA_BIN}" -version 2>&1 | head -1 | awk -F '"' '{print $2}' | cut -d'.' -f1)

if [[ "${JAVA_MAJOR_INSTALLED}" -lt 17 ]]; then
    echo "[ERROR] Kafka 4.x requires Java 17 or higher. Found major version: ${JAVA_MAJOR_INSTALLED}"
    exit 1
fi

# -----------------------------------------------------------------------------
# 11. EXPORT FOR DOWNSTREAM SCRIPTS
# -----------------------------------------------------------------------------
export JAVA_HOME
export JAVA_MAJOR

echo "[SUCCESS] Script 08: Java is ready."
echo "  JAVA_HOME: ${JAVA_HOME}"
echo "  Version:   ${JAVA_VERSION_OUTPUT}"
