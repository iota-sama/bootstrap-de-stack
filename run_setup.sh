#!/usr/bin/env bash
set -euo pipefail

# @description: Entry point for DE-Stack provisioning.
# @script: run_setup.sh
# @author: [Nishchay Dubey/iota-sama]


# -----------------------------------------------------------------------------
# 0. PREFLIGHT CHECKS & PRIVILEGE SETUP
# -----------------------------------------------------------------------------

# Warn if running in a shell that may have stale variables from a previous run
if [[ -n "${KAFKA_PORT:-}" ]] || [[ -n "${PG_PORT:-}" ]] || [[ -n "${AIRFLOW_PORT:-}" ]]; then
    echo "[WARN] Detected service port variables already set in the environment."
    echo "[WARN] This may indicate a previous factory run in the same shell session."
    echo "[WARN] For reliable results, run ./run_setup.sh in a fresh terminal."
    echo ""
fi

# Parse optional --force flag
FORCE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "[ERROR] Unknown argument: $1"
            echo "Usage: ./run_setup.sh [--force]"
            exit 1
            ;;
    esac
done

# Validate sudo access or ask for credentials once
sudo -v

# Keep user credentials alive for the script's lifetime in the background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!

# -----------------------------------------------------------------------------
# CLEANUP HANDLER
# Runs on script exit (success, failure, or interrupt).
# Ensures no orphaned processes are left behind if the factory fails mid-run.
# -----------------------------------------------------------------------------
cleanup() {
    local exit_code=$?
    
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    
    if [[ -n "${CONNECT_RUNTIME_DIR:-}" ]] && [[ -f "${CONNECT_RUNTIME_DIR}/connect.pid" ]]; then
        CONNECT_PID=$(cat "${CONNECT_RUNTIME_DIR}/connect.pid" 2>/dev/null)
        kill "${CONNECT_PID}" 2>/dev/null || true
        rm -f "${CONNECT_RUNTIME_DIR}/connect.pid"
    fi

    if [[ -n "${SCHEMA_REGISTRY_RUNTIME_DIR:-}" ]] && [[ -f "${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid" ]]; then
        SR_PID=$(cat "${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid" 2>/dev/null)
        kill "${SR_PID}" 2>/dev/null || true
        rm -f "${SCHEMA_REGISTRY_RUNTIME_DIR}/schema-registry.pid"
    fi

    if [[ -n "${KAFKA_RUNTIME_DIR:-}" ]] && [[ -f "${KAFKA_RUNTIME_DIR}/kafka.pid" ]]; then
        KAFKA_PID=$(cat "${KAFKA_RUNTIME_DIR}/kafka.pid" 2>/dev/null)
        kill "${KAFKA_PID}" 2>/dev/null || true
        rm -f "${KAFKA_RUNTIME_DIR}/kafka.pid"
    fi
    
    if [[ -n "${AIRFLOW_RUNTIME_DIR:-}" ]]; then
        if [[ -f "${AIRFLOW_RUNTIME_DIR}/airflow-api-server.pid" ]]; then
            API_PID=$(cat "${AIRFLOW_RUNTIME_DIR}/airflow-api-server.pid" 2>/dev/null)
            kill "${API_PID}" 2>/dev/null || true
            rm -f "${AIRFLOW_RUNTIME_DIR}/airflow-api-server.pid"
        fi
        if [[ -f "${AIRFLOW_RUNTIME_DIR}/airflow-scheduler.pid" ]]; then
            SCHED_PID=$(cat "${AIRFLOW_RUNTIME_DIR}/airflow-scheduler.pid" 2>/dev/null)
            kill "${SCHED_PID}" 2>/dev/null || true
            rm -f "${AIRFLOW_RUNTIME_DIR}/airflow-scheduler.pid"
        fi
    fi
    
    if [[ -n "${PG_BIN_PATH:-}" ]] && [[ -n "${PGDATA:-}" ]]; then
        "${PG_BIN_PATH}/pg_ctl" -D "${PGDATA}" stop -m fast 2>/dev/null || true
    fi
    
    echo "[INFO] Cleanup complete."
    exit "${exit_code}"
}

trap cleanup EXIT INT TERM

export DEBIAN_FRONTEND=noninteractive

# -----------------------------------------------------------------------------
# 1. BOOTSTRAP DIRECTORY & PATH EXPORTS
# -----------------------------------------------------------------------------
BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export BOOTSTRAP_DIR
export REGISTRY_FILE="${BOOTSTRAP_DIR}/lab_registry.csv"

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

set -a
source "$ENV_FILE"
set +a

# -----------------------------------------------------------------------------
# 3. LAB PATH RESOLUTION & COLLISION DETECTION
# -----------------------------------------------------------------------------
PARENT_DIR="$(dirname "${BOOTSTRAP_DIR}")"
: "${LAB_HOME:="${PARENT_DIR}/de_lab_testing"}"
export LAB_HOME

LAB_NAME=$(basename "${LAB_HOME}")
ORIGINAL_LAB_NAME="${LAB_NAME}"
ORIGINAL_LAB_HOME="${LAB_HOME}"
LAB_PARENT=$(dirname "${LAB_HOME}")
FACTORY_STATE="${LAB_HOME}/configs/factory.state"

# -----------------------------------------------------------------------------
# 4. FACTORY STATE MANAGEMENT
# -----------------------------------------------------------------------------
if [[ -f "${FACTORY_STATE}" ]]; then
    source "${FACTORY_STATE}"
    
    if [[ "${STATUS:-}" == "complete" ]] && [[ "${FORCE}" == "false" ]]; then
        echo "[ERROR] A completed lab already exists at: ${LAB_HOME}"
        echo "[ERROR] Use --force to reprovision, or delete the lab first."
        echo "[ERROR] Delete lab: bash utils/delete_lab.sh --lab-path ${LAB_HOME}"
        exit 1
    fi
    
    if [[ "${STATUS:-}" == "complete" ]] && [[ "${FORCE}" == "true" ]]; then
        # Shut down any running services before reprovisioning.
        if [[ -f "${LAB_HOME}/bin/lab_shutdown.sh" ]]; then
            echo "[INFO] Lab may be running. Shutting down before reprovisioning..."
            (
                source "${LAB_HOME}/configs/state.env" 2>/dev/null || true
                if [[ -x "${LAB_HOME}/bin/lab_shutdown.sh" ]]; then
                    "${LAB_HOME}/bin/lab_shutdown.sh" 2>/dev/null || true
                fi
            )
            echo "[INFO] Shutdown complete."
        fi

        echo "[INFO] Force flag set. Re-provisioning completed lab..."
        sed -i "s/^STATUS=.*/STATUS=in_progress/" "${FACTORY_STATE}"
        sed -i "s/^LAST_COMPLETED=.*/LAST_COMPLETED=/" "${FACTORY_STATE}"
        sed -i "s/^CURRENT_SCRIPT=.*/CURRENT_SCRIPT=/" "${FACTORY_STATE}"

    elif [[ "${STATUS:-}" == "in_progress" ]]; then
        echo "[INFO] Interrupted provisioning detected."
        echo "[INFO] Last completed script: ${LAST_COMPLETED:-none}"
        echo "[INFO] Resuming from the beginning (scripts are idempotent)..."
        echo ""
    fi
else
    # Fresh provisioning — no factory state exists
    SUFFIX=1
    while grep -q ",${LAB_NAME}," "${REGISTRY_FILE}" 2>/dev/null || [[ -d "${LAB_HOME}" ]]; do
        LAB_NAME="${ORIGINAL_LAB_NAME}_${SUFFIX}"
        LAB_HOME="${LAB_PARENT}/${LAB_NAME}"
        SUFFIX=$((SUFFIX + 1))
    done
    
    if [[ "${LAB_HOME}" != "${ORIGINAL_LAB_HOME}" ]]; then
        echo "[INFO] Name '${ORIGINAL_LAB_NAME}' conflicts with existing lab or registry entry."
        echo "[INFO] Using '${LAB_HOME}' instead."
        echo ""
    fi
    export LAB_HOME
    FRESH_PROVISIONING=true
fi

# -----------------------------------------------------------------------------
# 5. FACTORY STATE HELPER FUNCTIONS
# -----------------------------------------------------------------------------
mark_script_start() {
    local script_name="$1"
    if [[ -f "${FACTORY_STATE}" ]]; then
        sed -i "s/^CURRENT_SCRIPT=.*/CURRENT_SCRIPT=${script_name}/" "${FACTORY_STATE}"
    fi
}

mark_script_complete() {
    local script_name="$1"
    if [[ -f "${FACTORY_STATE}" ]]; then
        sed -i "s/^LAST_COMPLETED=.*/LAST_COMPLETED=${script_name}/" "${FACTORY_STATE}"
    fi
}

mark_lab_complete() {
    if [[ -f "${FACTORY_STATE}" ]]; then
        sed -i "s/^STATUS=.*/STATUS=complete/" "${FACTORY_STATE}"
        sed -i "s/^CURRENT_SCRIPT=.*/CURRENT_SCRIPT=/" "${FACTORY_STATE}"
        echo "COMPLETED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "${FACTORY_STATE}"
    fi
}

# -----------------------------------------------------------------------------
# 6. EXECUTION PHASE
# -----------------------------------------------------------------------------

echo "[PROGRESS] Initializing Layer 1: Base Environment..."
mark_script_start "00_base_setup.sh"
source "${BOOTSTRAP_DIR}/scripts/00_base_setup.sh"
mark_script_complete "00_base_setup.sh"

# Create factory state file for fresh provisioning (STACK_ID exists after 00_base_setup.sh)
if [[ "${FRESH_PROVISIONING:-false}" == "true" ]]; then
    mkdir -p "${LAB_HOME}/configs"
    cat > "${FACTORY_STATE}" <<INNEREOF
STATUS=in_progress
LAB_HOME=${LAB_HOME}
LAB_NAME=${LAB_NAME}
STACK_ID=${STACK_ID}
CURRENT_SCRIPT=00_base_setup.sh
LAST_COMPLETED=00_base_setup.sh
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
INNEREOF
fi

echo "[SUCCESS] Layer 1 Provisioning Complete."

echo "[PROGRESS] Initializing Layer 2: PostgreSQL Engine..."
mark_script_start "01_setup_pg_engine.sh"
source "${BOOTSTRAP_DIR}/scripts/01_setup_pg_engine.sh"
mark_script_complete "01_setup_pg_engine.sh"
echo "[SUCCESS] PostgreSQL Engine Setup Complete."

echo "[PROGRESS] Initializing PostgreSQL Runtime Service..."
mark_script_start "02_runtime_pg_service.sh"
source "${BOOTSTRAP_DIR}/scripts/02_runtime_pg_service.sh"
mark_script_complete "02_runtime_pg_service.sh"
echo "[SUCCESS] PostgreSQL Runtime Service Active."

echo "[PROGRESS] Provisioning Database Schema..."
mark_script_start "03_provision_pg_schema.sh"
source "${BOOTSTRAP_DIR}/scripts/03_provision_pg_schema.sh"
mark_script_complete "03_provision_pg_schema.sh"
echo "[SUCCESS] Database Schema Provisioned."

echo "[PROGRESS] Initializing Layer 3: Airflow Engine..."
mark_script_start "04_setup_airflow_venv.sh"
source "${BOOTSTRAP_DIR}/scripts/04_setup_airflow_venv.sh"
mark_script_complete "04_setup_airflow_venv.sh"
echo "[SUCCESS] Airflow Engine Setup Complete."

echo "[PROGRESS] Provisioning Airflow Metadata Database..."
mark_script_start "05_provision_airflow_db.sh"
source "${BOOTSTRAP_DIR}/scripts/05_provision_airflow_db.sh"
mark_script_complete "05_provision_airflow_db.sh"
echo "[SUCCESS] Airflow Metadata Database Ready."

echo "[PROGRESS] Configuring Airflow..."
mark_script_start "06_configure_airflow.sh"
source "${BOOTSTRAP_DIR}/scripts/06_configure_airflow.sh"
mark_script_complete "06_configure_airflow.sh"
echo "[SUCCESS] Airflow Configuration Complete."

echo "[PROGRESS] Starting Airflow Runtime Services..."
mark_script_start "07_runtime_airflow.sh"
source "${BOOTSTRAP_DIR}/scripts/07_runtime_airflow.sh"
mark_script_complete "07_runtime_airflow.sh"
echo "[SUCCESS] Airflow Runtime Services Active."

echo "[PROGRESS] Initializing Layer 4: Java Runtime..."
mark_script_start "08_setup_java.sh"
source "${BOOTSTRAP_DIR}/scripts/08_setup_java.sh"
mark_script_complete "08_setup_java.sh"
echo "[SUCCESS] Java Runtime Ready."

echo "[PROGRESS] Initializing Kafka Engine..."
mark_script_start "09_setup_kafka.sh"
source "${BOOTSTRAP_DIR}/scripts/09_setup_kafka.sh"
mark_script_complete "09_setup_kafka.sh"
echo "[SUCCESS] Kafka Engine Setup Complete."

echo "[PROGRESS] Starting Kafka Runtime Service..."
mark_script_start "10_runtime_kafka.sh"
source "${BOOTSTRAP_DIR}/scripts/10_runtime_kafka.sh"
mark_script_complete "10_runtime_kafka.sh"
echo "[SUCCESS] Kafka Runtime Service Active."

echo "[PROGRESS] Initializing Schema Registry Engine..."
mark_script_start "11_setup_schema_registry.sh"
source "${BOOTSTRAP_DIR}/scripts/11_setup_schema_registry.sh"
mark_script_complete "11_setup_schema_registry.sh"
echo "[SUCCESS] Schema Registry Engine Ready."

echo "[PROGRESS] Starting Schema Registry Runtime..."
mark_script_start "12_runtime_schema_registry.sh"
source "${BOOTSTRAP_DIR}/scripts/12_runtime_schema_registry.sh"
mark_script_complete "12_runtime_schema_registry.sh"
echo "[SUCCESS] Schema Registry Runtime Active."

echo "[PROGRESS] Initializing Kafka Connect & CDC Plugins..."
mark_script_start "13_setup_connect.sh"
source "${BOOTSTRAP_DIR}/scripts/13_setup_connect.sh"
mark_script_complete "13_setup_connect.sh"
echo "[SUCCESS] Kafka Connect Plugins Ready."

echo "[PROGRESS] Starting Kafka Connect & Debezium CDC..."
mark_script_start "14_runtime_connect.sh"
source "${BOOTSTRAP_DIR}/scripts/14_runtime_connect.sh"
mark_script_complete "14_runtime_connect.sh"
echo "[SUCCESS] Kafka Connect & CDC Pipeline Active."

echo "[PROGRESS] Seeding Airflow Streaming Connections..."
mark_script_start "15_seed_airflow_kafka.sh"
source "${BOOTSTRAP_DIR}/scripts/15_seed_airflow_kafka.sh"
mark_script_complete "15_seed_airflow_kafka.sh"
echo "[SUCCESS] Airflow Streaming Connections Seeded."

echo "[PROGRESS] Assembling Lab..."
mark_script_start "97_assemble_lab.sh"
source "${BOOTSTRAP_DIR}/scripts/97_assemble_lab.sh"
mark_script_complete "97_assemble_lab.sh"
echo "[SUCCESS] Lab Assembly Complete."

echo "[PROGRESS] Running Integration Tests..."
mark_script_start "98_run_tests.sh"
source "${BOOTSTRAP_DIR}/scripts/98_run_tests.sh"
mark_script_complete "98_run_tests.sh"
echo "[SUCCESS] Integration Tests Complete."

echo "[PROGRESS] Finalizing Lab (Cold Delivery)..."
mark_script_start "99_finalize_lab.sh"
source "${BOOTSTRAP_DIR}/scripts/99_finalize_lab.sh"
mark_script_complete "99_finalize_lab.sh"
mark_lab_complete
echo "[SUCCESS] Lab Finalized and Delivered Cold."


echo "======================================================="
echo "[COMPLETE] DE Lab Factory provisioning finished."
echo "Lab Location: ${LAB_HOME}"
echo "Start Lab:   source ${LAB_HOME}/bin/lab_entry.sh"
echo "Stop Lab:    bash ${LAB_HOME}/bin/lab_shutdown.sh"
echo "Delete Lab:  bash ${BOOTSTRAP_DIR}/utils/delete_lab.sh --lab-path ${LAB_HOME}"
echo "======================================================="
