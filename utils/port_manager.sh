#!/usr/bin/env bash
set -euo pipefail

# @description: Port allocation and discovery for the DE Lab Factory.
#              Ensures idempotent port assignment across multiple labs.
# @usage:       port_manager.sh --service <name> --lab-name <name> [--default-port <num>]
# @utility:     port_manager.sh
# @author:      [Nishchay Dubey/iota-sama]

# -----------------------------------------------------------------------------
# 1. PARSE ARGUMENTS
# -----------------------------------------------------------------------------
SERVICE=""
LAB_NAME=""
DEFAULT_PORT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --service)
            SERVICE="$2"
            shift 2
            ;;
        --lab-name)
            LAB_NAME="$2"
            shift 2
            ;;
        --default-port)
            DEFAULT_PORT="$2"
            shift 2
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            echo "Usage: port_manager.sh --service <name> --lab-name <name> [--default-port <num>]"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ -z "${SERVICE}" || -z "${LAB_NAME}" ]]; then
    echo "[ERROR] --service and --lab-name are required."
    exit 1
fi


# -----------------------------------------------------------------------------
# 2. LOCATE BOOTSTRAP DIRECTORY & REGISTRY FILE
# -----------------------------------------------------------------------------
# Use inherited value if available (from run_setup.sh sourcing)
if [[ -z "${REGISTRY_FILE:-}" ]]; then
    # Derive from script location: <BOOTSTRAP_DIR>/utils/port_manager.sh
    if [[ -z "${BOOTSTRAP_DIR:-}" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        BOOTSTRAP_DIR="$(dirname "${SCRIPT_DIR}")"
    fi
    : "${REGISTRY_FILE:="${BOOTSTRAP_DIR}/lab_registry.csv"}"
fi



# Initialize registry with header if it doesn't exist
if [[ ! -f "${REGISTRY_FILE}" ]]; then
    echo "date,lab_name,service,port" > "${REGISTRY_FILE}"
fi

# -----------------------------------------------------------------------------
# 3. HELPER: Check if port is actually in use on the system
# -----------------------------------------------------------------------------
is_port_in_use() {
    local port="$1"
    
    if command -v ss &>/dev/null; then
        # ss is available — use it
        ss -tuln 2>/dev/null | grep -q ":${port} " && return 0
    elif command -v netstat &>/dev/null; then
        # ss not found, fall back to netstat
        netstat -tuln 2>/dev/null | grep -q ":${port} " && return 0
    else
        # Neither tool available — can't check, assume free
        echo "[WARN] Neither ss nor netstat found. Skipping OS port check." >&2
    fi
    
    return 1  # Port appears free (or can't check)
}


# -----------------------------------------------------------------------------
# 4. CHECK IF PORT ALREADY ASSIGNED (Idempotency)
# -----------------------------------------------------------------------------

EXISTING_PORT=$(grep ",${LAB_NAME},${SERVICE}," "${REGISTRY_FILE}" 2>/dev/null | tail -1 | cut -d',' -f4 || true)

if [[ -n "${EXISTING_PORT}" ]]; then
    # The factory guarantees no zombie processes from previous runs.
    # If a previous factory run started this service, it was stopped on exit — success or failure.
    # Therefore, if the port is currently in use, it MUST be an external process.
    # Hence, warn, remove the stale registration, and reassign.
    if is_port_in_use "${EXISTING_PORT}"; then
        echo "[WARN] Registered port ${EXISTING_PORT} for ${SERVICE} is in use." >&2
        echo "[INFO] Removing stale registration and reassigning..." >&2
        sed -i "/,${LAB_NAME},${SERVICE},${EXISTING_PORT}$/d" "${REGISTRY_FILE}" 2>/dev/null || true
        # Fall through to new port assignment
    else
        echo "${EXISTING_PORT}"
        exit 0
    fi
fi


# -----------------------------------------------------------------------------
# 5. ASSIGN NEW PORT
# -----------------------------------------------------------------------------
declare -A DEFAULT_PORTS=(
    ["postgres"]="5432"
    ["airflow"]="8080"
    ["kafka_broker"]="9092"
    ["kafka_controller"]="9093"
    ['kafka_internal']="9094"
    ["schema_registry"]="8081"
    ["schema_registry_management"]="9000"
    ["kafka_connect"]="8083"
    ["spark_master"]="7077"
    ["spark_ui"]="8080"
)

if [[ -n "${DEFAULT_PORT}" ]]; then
    CANDIDATE_PORT="${DEFAULT_PORT}"
elif [[ -n "${DEFAULT_PORTS[${SERVICE}]:-}" ]]; then
    CANDIDATE_PORT="${DEFAULT_PORTS[${SERVICE}]}"
else
    CANDIDATE_PORT="9000"
fi

USED_PORTS=$(cut -d',' -f4 "${REGISTRY_FILE}" | tail -n +2 | sort -n | uniq || true)

ASSIGNED_PORT=""
MAX_ATTEMPTS=1000
ATTEMPT=0

while [[ -z "${ASSIGNED_PORT}" && ${ATTEMPT} -lt ${MAX_ATTEMPTS} ]]; do
    # Check registry
    if echo "${USED_PORTS}" | grep -q "^${CANDIDATE_PORT}$"; then
        CANDIDATE_PORT=$((CANDIDATE_PORT + 1))
        ATTEMPT=$((ATTEMPT + 1))
        continue
    fi
    # Check OS
    if is_port_in_use "${CANDIDATE_PORT}"; then
        echo "[WARN] Port ${CANDIDATE_PORT} is in use by another process. Skipping." >&2
        CANDIDATE_PORT=$((CANDIDATE_PORT + 1))
        ATTEMPT=$((ATTEMPT + 1))
        continue
    fi
    ASSIGNED_PORT="${CANDIDATE_PORT}"
done

if [[ -z "${ASSIGNED_PORT}" ]]; then
    echo "[ERROR] Could not find available port after ${MAX_ATTEMPTS} attempts." >&2
    exit 1
fi




# -----------------------------------------------------------------------------
# 6. REGISTER AND RETURN
# -----------------------------------------------------------------------------
echo "$(date +%Y-%m-%d),${LAB_NAME},${SERVICE},${ASSIGNED_PORT}" >> "${REGISTRY_FILE}"
echo "${ASSIGNED_PORT}"