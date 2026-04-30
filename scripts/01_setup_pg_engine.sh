#!/usr/bin/env bash
set -euo pipefail


# @description: System-wide install of PG18 & Local initialization of Data Cluster.
# @script: 01_setup_pg_engine.sh
# @author: [Nishchay Dubey/iota-sama]



# 1. PRIVILEGE CHECK (Fail-Fast)
# -----------------------------------------------------------------------------
if ! sudo -n true 2>/dev/null; then
    echo "[ERROR] This script (01_setup_pg_engine.sh) requires sudo privileges to install system binaries."
    echo "Please run this script via run_setup.sh or run 'sudo -v' before executing it directly."
    exit 1
fi


# 2. ENVIRONMENT PATHS & DEFAULTS
# -----------------------------------------------------------------------------
# Dynamically determine the lab root relative to script location
PARENT_DIR="$(dirname "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")")"

# Respect existing environment variables, otherwise use defaults
: "${LAB_HOME:="${PARENT_DIR}/de_lab_testing"}"
: "${PG_VERSION:="18"}"
: "${PGDATA:="${LAB_HOME}/data/postgres"}"
: "${PG_BIN_PATH:="/usr/lib/postgresql/${PG_VERSION}/bin"}"

# Export for child processes
export LAB_HOME PGDATA PG_BIN_PATH PG_VERSION


echo "[PROGRESS] Starting Layer 2: PostgreSQL ${PG_VERSION} Engine Setup..."


# 3. INSTALL SYSTEM BINARIES (The "Engine")
# -----------------------------------------------------------------------------
if [[ ! -f /etc/apt/sources.list.d/pgdg.list ]]; then
    echo "[INFO] Adding official PostgreSQL (PGDG) repository..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" | sudo tee /etc/apt/sources.list.d/pgdg.list
    sudo apt update
fi

echo "[INFO] Ensuring PostgreSQL ${PG_VERSION} binaries are installed..."
sudo apt install -y postgresql-${PG_VERSION} postgresql-client-${PG_VERSION}



# 3. INITIALIZE DATA CLUSTER
# -----------------------------------------------------------------------------

# Ensure the directory exists and has correct permissions
mkdir -p "$PGDATA"
chmod 0700 "$PGDATA" # Postgres requires strict 0700 permissions

# Idempotency Check: Only initdb if PG_VERSION doesn't exist
if [[ ! -f "${PGDATA}/PG_VERSION" ]]; then
    echo "[INFO] Initializing new cluster in $PGDATA..."
    
    "${PG_BIN_PATH}/initdb" -D "$PGDATA" \
        --auth-local=peer \
        --auth-host=scram-sha-256 \
        --data-checksums \
        --encoding=UTF8 \
        --locale=en_US.UTF-8
    
    echo "[SUCCESS] PostgreSQL ${PG_VERSION} cluster initialized."
else
    echo "[INFO] Existing cluster detected. Skipping initialization."
fi


echo "[SUCCESS] Script 01: PostgreSQL Engine and Data Cluster are ready."
