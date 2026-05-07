#!/usr/bin/env bash
# @description: Generates the user-editable lab config file (lab_config.sh).
#              Only created if it doesn't exist — preserves user edits.
#              Sourced by 98_assemble_lab.sh — inherits all variables.
# @generator: generate_lab_config.sh
# @author: [Nishchay Dubey/iota-sama]

set -euo pipefail

# -----------------------------------------------------------------------------
# 1. ENVIRONMENT VALIDATION
# -----------------------------------------------------------------------------
: "${LAB_HOME:?LAB_HOME is not set. Run via 98_assemble_lab.sh}"

USER_CONFIG="${LAB_HOME}/configs/lab_config.sh"

# -----------------------------------------------------------------------------
# 2. GENERATE USER CONFIG (Only if not exists)
# -----------------------------------------------------------------------------
if [[ ! -f "${USER_CONFIG}" ]]; then
    cat > "${USER_CONFIG}" <<'USERCONFEOF'
# ==========================================================
# LAB CONFIGURATION — User-Editable Settings
# ==========================================================
# This file is generated once and never overwritten.
# Add your custom environment variables and aliases below.
# ==========================================================
#
# TIP: For PostgreSQL tuning (work_mem, effective_cache_size,
# wal_level, etc.), edit the configuration file directly:
#
#   nano ${PGDATA}/custom_lab.conf
#
# Then restart PostgreSQL:
#
#   ${PG_BIN_PATH}/pg_ctl -D ${PGDATA} restart
#
# All variables are available after sourcing:
#
#   source ${LAB_HOME}/bin/lab_entry.sh
# ==========================================================
USERCONFEOF
    echo "[INFO] User config created: ${USER_CONFIG}"
else
    echo "[INFO] User config already exists. Skipping (preserving user edits)."
fi