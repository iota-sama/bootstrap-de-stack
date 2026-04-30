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
trap 'kill ${SUDO_KEEPALIVE_PID} 2>/dev/null' EXIT

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

echo "[PROGRESS] Generating Lab Manifest..."
source "${BOOTSTRAP_DIR}/scripts/99_generate_lab_manifest.sh"
echo "[SUCCESS] Lab Manifest Generated."

echo "======================================================="
echo "[COMPLETE] DE Lab Factory provisioning finished."
echo "Lab Location: ${LAB_HOME}"
echo "Entry Point:  source ${LAB_HOME}/bin/lab_entry.sh"
echo "======================================================="
