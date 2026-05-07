#!/usr/bin/env bash
set -euo pipefail

# @description: Permanently delete a lab and all its resources.
#              Requires the absolute path to the lab directory.
# @usage:       delete_lab.sh --lab-path <absolute-path> [--force]
# @author:      [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. PARSE ARGUMENTS
# -----------------------------------------------------------------------------
LAB_PATH=""
FORCE=false

usage() {
    echo "Usage: delete_lab.sh --lab-path <absolute-path> [--force]"
    echo ""
    echo "  --lab-path   Absolute path to the lab directory to delete"
    echo "  --force      Skip confirmation prompt"
    echo ""
    echo "WARNING: This operation is irreversible. All lab data, configs,"
    echo "         and secrets will be permanently destroyed."
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lab-path)
            LAB_PATH="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            usage
            ;;
    esac
done

if [[ -z "${LAB_PATH}" ]]; then
    echo "[ERROR] --lab-path is required."
    usage
fi

# -----------------------------------------------------------------------------
# 2. VALIDATE THE LAB PATH
# -----------------------------------------------------------------------------

# Must be an absolute path
if [[ "${LAB_PATH}" != /* ]]; then
    echo "[ERROR] --lab-path must be an absolute path (must start with /)."
    echo "Provided: ${LAB_PATH}"
    exit 1
fi

# Resolve to canonical absolute path (handles trailing slashes, symlinks, etc.)
# Silence cd errors — we validate the directory exists in the next check
LAB_HOME="$(cd "$(dirname "${LAB_PATH}")" 2>/dev/null && pwd)/$(basename "${LAB_PATH}")"

if [[ ! -d "${LAB_HOME}" ]]; then
    echo "[ERROR] Directory not found: ${LAB_HOME}"
    exit 1
fi

if [[ ! -f "${LAB_HOME}/configs/state.env" ]]; then
    echo "[ERROR] No lab found at ${LAB_HOME}"
    echo "The directory exists but does not contain configs/state.env."
    echo "This does not appear to be a bootstrap-de-stack lab."
    exit 1
fi

# -----------------------------------------------------------------------------
# 3. LOAD LAB STATE
# -----------------------------------------------------------------------------
source "${LAB_HOME}/configs/state.env"

# Validate critical state variables
if [[ -z "${LAB_NAME:-}" ]] || [[ -z "${STACK_ID:-}" ]]; then
    echo "[ERROR] State file is corrupted or incomplete."
    echo "LAB_NAME or STACK_ID is missing from state.env."
    exit 1
fi

# -----------------------------------------------------------------------------
# 4. LOCATE BOOTSTRAP DIRECTORY & REGISTRY
# -----------------------------------------------------------------------------
# Derive bootstrap directory from this script's own location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$(dirname "${SCRIPT_DIR}")"
REGISTRY_FILE="${BOOTSTRAP_DIR}/lab_registry.csv"

if [[ ! -f "${REGISTRY_FILE}" ]]; then
    echo "[WARN] Registry file not found: ${REGISTRY_FILE}"
    echo "The lab will be deleted but registry cleanup will be skipped."
fi

# -----------------------------------------------------------------------------
# 5. CONFIRMATION
# -----------------------------------------------------------------------------
echo ""
echo "======================================================="
echo "  DANGER: Irreversible Operation"
echo "======================================================="
echo "  Lab Name:    ${LAB_NAME}"
echo "  Stack ID:    ${STACK_ID}"
echo "  Location:    ${LAB_HOME}"
echo ""
echo "  This will:"
echo "  1. Stop all running services (PostgreSQL, Airflow)"
echo "  2. Delete all lab data, configs, DAGs, and secrets"
echo "  3. Remove lab from the factory port registry"
echo "======================================================="
echo ""

if [[ "${FORCE}" == "false" ]]; then
    read -p "Type 'DELETE' to confirm: " CONFIRM
    if [[ "${CONFIRM}" != "DELETE" ]]; then
        echo "[INFO] Deletion cancelled."
        exit 0
    fi
fi

# -----------------------------------------------------------------------------
# 6. STOP RUNNING PROCESSES
# -----------------------------------------------------------------------------
echo "[PROGRESS] Stopping lab processes..."

# Use the lab's own shutdown script if it exists
if [[ -f "${LAB_HOME}/bin/lab_shutdown.sh" ]]; then
    bash "${LAB_HOME}/bin/lab_shutdown.sh" 2>/dev/null || true
else
    # Manual shutdown as fallback
    echo "[INFO] No shutdown script found. Performing manual shutdown..."

    # Stop Airflow if PID files exist
    if [[ -n "${AIRFLOW_RUN_DIR:-}" ]]; then
        if [[ -f "${AIRFLOW_RUN_DIR}/airflow-api-server.pid" ]]; then
            API_PID=$(cat "${AIRFLOW_RUN_DIR}/airflow-api-server.pid" 2>/dev/null)
            if [[ -n "${API_PID}" ]]; then
                kill "${API_PID}" 2>/dev/null || true
                rm -f "${AIRFLOW_RUN_DIR}/airflow-api-server.pid"
            fi
        fi
        if [[ -f "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid" ]]; then
            SCHED_PID=$(cat "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid" 2>/dev/null)
            if [[ -n "${SCHED_PID}" ]]; then
                kill "${SCHED_PID}" 2>/dev/null || true
                rm -f "${AIRFLOW_RUN_DIR}/airflow-scheduler.pid"
            fi
        fi
    fi

    # Stop PostgreSQL if running
    if [[ -n "${PG_BIN_PATH:-}" ]] && [[ -n "${PGDATA:-}" ]] && [[ -n "${PG_PORT:-}" ]]; then
        if "${PG_BIN_PATH}/pg_isready" -p "${PG_PORT}" -h localhost >/dev/null 2>&1; then
            "${PG_BIN_PATH}/pg_ctl" -D "${PGDATA}" stop -m fast 2>/dev/null || true
        fi
    fi
fi

echo "[INFO] Lab processes stopped."

# -----------------------------------------------------------------------------
# 7. DELETE LAB DIRECTORY
# -----------------------------------------------------------------------------
echo "[PROGRESS] Deleting lab directory: ${LAB_HOME}"

rm -rf "${LAB_HOME}"

if [[ -d "${LAB_HOME}" ]]; then
    echo "[ERROR] Failed to delete lab directory. Check permissions."
    exit 1
fi

echo "[INFO] Lab directory deleted."

# -----------------------------------------------------------------------------
# 8. CLEAN UP REGISTRY
# -----------------------------------------------------------------------------
if [[ -f "${REGISTRY_FILE}" ]]; then
    # Remove all registry entries for this lab (all services)
    sed -i "/,${LAB_NAME},/d" "${REGISTRY_FILE}" 2>/dev/null || true
    echo "[INFO] Registry entries removed for lab '${LAB_NAME}'."
fi

# -----------------------------------------------------------------------------
# 9. SUMMARY
# -----------------------------------------------------------------------------
echo "======================================================="
echo "[SUCCESS] Lab '${LAB_NAME}' has been permanently deleted."
echo "======================================================="
