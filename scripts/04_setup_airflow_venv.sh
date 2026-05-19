#!/usr/bin/env bash
set -euo pipefail

# @description: Install Apache Airflow and providers in a pinned Python virtual environment.
# @script: 04_setup_airflow_venv.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run via run_setup.sh}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"

# -----------------------------------------------------------------------------
# 2. DEFAULTS & CONFIGURATION
# -----------------------------------------------------------------------------
: "${AIRFLOW_VERSION:="3.2.0"}"
: "${PYTHON_BIN:="python3"}"

AIRFLOW_VENV="${LAB_HOME}/engine/airflow"
AIRFLOW_HOME="${LAB_HOME}/configs"
export AIRFLOW_HOME AIRFLOW_VENV


# -----------------------------------------------------------------------------
# 4. PYTHON VERSION VALIDATION
# -----------------------------------------------------------------------------
echo "[PROGRESS] Starting Airflow installation in virtual environment..."

if ! command -v "${PYTHON_BIN}" &>/dev/null; then
    echo "[ERROR] ${PYTHON_BIN} not found. Ensure 00_base_setup.sh ran successfully."
    exit 1
fi

PYTHON_VERSION=$("${PYTHON_BIN}" --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR=$(echo "${PYTHON_VERSION}" | cut -d'.' -f1)
PYTHON_MINOR=$(echo "${PYTHON_VERSION}" | cut -d'.' -f2)

echo "[INFO] Detected Python version: ${PYTHON_VERSION}"

if [[ "${PYTHON_MAJOR}" -lt 3 ]] || { [[ "${PYTHON_MAJOR}" -eq 3 ]] && [[ "${PYTHON_MINOR}" -lt 10 ]]; }; then
    echo "[ERROR] Airflow 3.x requires Python 3.10 or higher. Found: ${PYTHON_VERSION}"
    exit 1
fi

# -----------------------------------------------------------------------------
# 5. CREATE VIRTUAL ENVIRONMENT (Idempotent)
# -----------------------------------------------------------------------------
if [[ -f "${AIRFLOW_VENV}/bin/activate" ]]; then
    echo "[INFO] Airflow virtual environment already exists. Skipping venv creation."
else
    echo "[INFO] Creating Python virtual environment at ${AIRFLOW_VENV}..."
    "${PYTHON_BIN}" -m venv "${AIRFLOW_VENV}"
    echo "[SUCCESS] Virtual environment created."
fi

# -----------------------------------------------------------------------------
# 6. INSTALL AIRFLOW (Idempotent)
# -----------------------------------------------------------------------------
AIRFLOW_CHECK=$("${AIRFLOW_VENV}/bin/pip" show apache-airflow 2>/dev/null | grep "^Version:" | awk '{print $2}' || true)

if [[ "${AIRFLOW_CHECK}" == "${AIRFLOW_VERSION}" ]]; then
    echo "[INFO] Airflow ${AIRFLOW_VERSION} already installed. Skipping pip install."
else
    if [[ -n "${AIRFLOW_CHECK}" ]]; then
        echo "[INFO] Airflow version ${AIRFLOW_CHECK} found. Upgrading to ${AIRFLOW_VERSION}..."
    fi

    echo "[INFO] Installing Apache Airflow ${AIRFLOW_VERSION} with constraints..."
    echo "[INFO] This may take several minutes. Please wait..."

    CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_MAJOR}.${PYTHON_MINOR}.txt"

    "${AIRFLOW_VENV}/bin/pip" install --upgrade pip setuptools wheel --quiet

    if ! "${AIRFLOW_VENV}/bin/pip" install \
        "apache-airflow==${AIRFLOW_VERSION}" \
        --constraint "${CONSTRAINT_URL}" \
        --quiet > /dev/null 2>&1; then
        
        echo "[WARN] Constraints file not available. Installing without constraints..."
        "${AIRFLOW_VENV}/bin/pip" install "apache-airflow==${AIRFLOW_VERSION}"
    fi

    echo "[SUCCESS] Apache Airflow ${AIRFLOW_VERSION} installed."
fi

# -----------------------------------------------------------------------------
# 7. VERIFY INSTALLATION
# -----------------------------------------------------------------------------
echo "[INFO] Verifying Airflow installation..."
INSTALLED_VERSION=$("${AIRFLOW_VENV}/bin/airflow" version 2>/dev/null || echo "ERROR")

if [[ "${INSTALLED_VERSION}" == "ERROR" ]]; then
    echo "[ERROR] Airflow CLI not responding. Installation may have failed."
    exit 1
fi

echo "[INFO] Airflow CLI version: ${INSTALLED_VERSION}"

# Verify PostgreSQL provider is available
if "${AIRFLOW_VENV}/bin/airflow" providers list 2>/dev/null | grep -q "postgres"; then
    echo "[INFO] PostgreSQL provider detected."
else
    echo "[WARN] PostgreSQL provider not detected. Installing explicitly..."
    "${AIRFLOW_VENV}/bin/pip" install --quiet "apache-airflow-providers-postgres"
fi

# Install Apache Kafka provider for streaming integration (Phase 4)
if "${AIRFLOW_VENV}/bin/airflow" providers list 2>/dev/null | grep -q "apache.kafka"; then
    echo "[INFO] Apache Kafka provider detected."
else
    echo "[INFO] Installing Apache Kafka provider..."
    "${AIRFLOW_VENV}/bin/pip" install --quiet "apache-airflow-providers-apache-kafka"
    echo "[SUCCESS] Apache Kafka provider installed."
fi

# -----------------------------------------------------------------------------
# 8. SUMMARY
# -----------------------------------------------------------------------------

echo "[SUCCESS] Script 04: Airflow virtual environment is ready."
echo "  Venv:    ${AIRFLOW_VENV}"
echo "  Version: ${INSTALLED_VERSION}"
echo "  AIRFLOW_HOME: ${AIRFLOW_HOME}"