#!/usr/bin/env bash
set -euo pipefail

# @description: Assembles the lab by orchestrating all generator scripts.
#              Creates directories, state, entry point, config, and shutdown script.
# @script: 98_assemble_lab.sh
# @author: [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run base setup first.}"
: "${STACK_ID:?STACK_ID is not set.}"
: "${ENV_NAME:?ENV_NAME is not set.}"
: "${BOOTSTRAP_DIR:?BOOTSTRAP_DIR is not set. Run via run_setup.sh}"

GENERATORS_DIR="${BOOTSTRAP_DIR}/scripts/generators"


# -----------------------------------------------------------------------------
# 2. CREATE DIRECTORIES
# -----------------------------------------------------------------------------
echo "[PROGRESS] Assembling lab: ${ENV_NAME} (${STACK_ID})"
mkdir -p "${LAB_HOME}/bin"
mkdir -p "${LAB_HOME}/configs"

# -----------------------------------------------------------------------------
# 3. RUN GENERATORS IN SEQUENCE
# -----------------------------------------------------------------------------
echo "[INFO] Generating state file..."
source "${GENERATORS_DIR}/generate_state_env.sh"

echo "[INFO] Generating lab config..."
source "${GENERATORS_DIR}/generate_lab_config.sh"

echo "[INFO] Generating lab entry point..."
source "${GENERATORS_DIR}/generate_lab_entry.sh"

echo "[INFO] Generating lab shutdown script..."
source "${GENERATORS_DIR}/generate_lab_shutdown.sh"

# -----------------------------------------------------------------------------
# 4. SET PERMISSIONS
# -----------------------------------------------------------------------------
chmod +x "${LAB_HOME}/bin/"*.sh 2>/dev/null || true

echo "[SUCCESS] Lab assembly complete."
echo "  Entry:    ${LAB_HOME}/bin/lab_entry.sh"
echo "  Shutdown: ${LAB_HOME}/bin/lab_shutdown.sh"
echo "  Config:   ${LAB_HOME}/configs/lab_config.sh"
echo "  State:    ${LAB_HOME}/configs/state.env"