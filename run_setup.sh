#!/usr/bin/env bash
set -euo pipefail

# @description: Entry point for DE-Stack provisioning.
# @script: run_setup.sh
# @author: [Nishchay Dubey/iota-sama]



# -----------------------------------------------------------------------------
# 0. PRIVILEGE & ENVIRONMENT SETUP
# -----------------------------------------------------------------------------
# Validate sudo access or ask for credentials once
sudo -v

# Keep user credentials alive for the script's lifetime in the background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

# -----------------------------------------------------------------------------
# Cleanup handler — runs on script exit (success, failure, or interrupt)
# Ensures no orphaned processes are left behind if the factory fails mid-run.
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    
    # Terminate the sudo keepalive background process
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    
    # Stop Airflow if it was started
    if [[ -n "${AIRFLOW_RUN_DIR:-}" ]]; then
        if [[ -f "${AIRFLOW_RUN_DIR}/airflow-api-server.pid" ]]; then
            API_PID=$(cat "${AIRFLOW_RUN_DIR}/airflow-api-server.pid" 2>/dev/null)
            kill "${API_PID}" 2>/dev/null || true
            rm -f "${AIRFLOW_RUN_DIR}/airflow-api-server.pid" 2>/dev/null
        fi
        if [[ -f "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid" ]]; then
            SCHED_PID=$(cat "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid" 2>/dev/null)
            kill "${SCHED_PID}" 2>/dev/null || true
            rm -f "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid" 2>/dev/null
        fi
    fi
    
    # Stop PostgreSQL if it was started
    if [[ -n "${PG_BIN_PATH:-}" ]] && [[ -n "${PGDATA:-}" ]]; then
        "${PG_BIN_PATH}/pg_ctl" -D "${PGDATA}" stop -m fast 2>/dev/null || true
    fi
    
    echo "[INFO] Cleanup complete."
    exit "${exit_code}"
}

# Register the cleanup handler for normal exit, Ctrl+C, and kill signal
trap cleanup EXIT INT TERM

# Prevent interactive prompts during package installation
export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# 1. BOOTSTRAP DIRECTORY & PATH EXPORTS
# -----------------------------------------------------------------------------
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BOOTSTRAP_DIR
export REGISTRY_FILE="${BOOTSTRAP_DIR}/lab_registry.csv"

# Ensure all scripts are executable
chmod +x "${BOOTSTRAP_DIR}"/*.sh 2>/dev/null || true
chmod +x "${BOOTSTRAP_DIR}/scripts/"*.sh 2>/dev/null || true
chmod +x "${BOOTSTRAP_DIR}/scripts/generators/"*.sh 2>/dev/null || true
chmod +x "${BOOTSTRAP_DIR}/utils/"*.sh 2>/dev/null || true

# -----------------------------------------------------------------------------
# 2. CONFIGURATION HANDSHAKE
# -----------------------------------------------------------------------------
if [[ -f "${BOOTSTRAP_DIR}/settings.env" ]]; then
    ENV_FILE="${BOOTSTRAP_DIR}/settings.env"
    echo "[INFO] Loading custom configuration from settings.env"
else
    ENV_FILE="${BOOTSTRAP_DIR}/settings.env.example"
    echo "-------------------------------------------------------"
    echo "[WARNING] settings.env not found!"
    echo "[WARNING] Falling back to template for testing mode."
    echo "-------------------------------------------------------"
fi

# Export Variables from the Environment File
set -a
source "$ENV_FILE"
set +a

# -----------------------------------------------------------------------------
# 3. EXECUTION PHASE
# -----------------------------------------------------------------------------

echo "[PROGRESS] Initializing Layer 1: Base Environment..."
source "${BOOTSTRAP_DIR}/scripts/00_base_setup.sh"
echo "[SUCCESS] Layer 1 Provisioning Complete."

echo "[PROGRESS] Initializing Layer 2: PostgreSQL Engine..."
source "${BOOTSTRAP_DIR}/scripts/01_setup_pg_engine.sh"
echo "[SUCCESS] PostgreSQL Engine Setup Complete."

echo "[PROGRESS] Initializing PostgreSQL Runtime Service..."
source "${BOOTSTRAP_DIR}/scripts/02_runtime_pg_service.sh"
echo "[SUCCESS] PostgreSQL Runtime Service Active."

echo "[PROGRESS] Provisioning Database Schema..."
source "${BOOTSTRAP_DIR}/scripts/03_provision_pg_schema.sh"
echo "[SUCCESS] Database Schema Provisioned."

echo "[PROGRESS] Initializing Layer 3: Airflow Engine..."
source "${BOOTSTRAP_DIR}/scripts/04_setup_airflow_venv.sh"
echo "[SUCCESS] Airflow Engine Setup Complete."

echo "[PROGRESS] Provisioning Airflow Metadata Database..."
source "${BOOTSTRAP_DIR}/scripts/05_provision_airflow_db.sh"
echo "[SUCCESS] Airflow Metadata Database Ready."

echo "[PROGRESS] Configuring Airflow..."
source "${BOOTSTRAP_DIR}/scripts/06_configure_airflow.sh"
echo "[SUCCESS] Airflow Configuration Complete."

echo "[PROGRESS] Starting Airflow Runtime Services..."
source "${BOOTSTRAP_DIR}/scripts/07_runtime_airflow.sh"
echo "[SUCCESS] Airflow Runtime Services Active."

echo "[PROGRESS] Assembling Lab Entry Point & Shutdown Scripts..."
source "${BOOTSTRAP_DIR}/scripts/98_assemble_lab.sh"
echo "[SUCCESS] Lab Assembly Complete."

echo "[PROGRESS] Finalizing Lab (Cold Delivery)..."
source "${BOOTSTRAP_DIR}/scripts/99_finalize_lab.sh"
echo "[SUCCESS] Lab Finalized and Delivered Cold."


echo "======================================================="
echo "[COMPLETE] DE Lab Factory provisioning finished."
echo "Lab Location: ${LAB_HOME}"
echo "Start Lab:   source ${LAB_HOME}/bin/lab_entry.sh"
echo "Stop Lab:    bash ${LAB_HOME}/bin/lab_shutdown.sh"
echo "Delete Lab:  bash ${BOOTSTRAP_DIR}/utils/delete_lab.sh --lab-path ${LAB_HOME}"
echo "======================================================="
