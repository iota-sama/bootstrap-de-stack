# @description: Entry point for DE-Stack provisioning.
# @author: [Nishchay Dubey/iota-sama]
# @version: 0.1.0-alpha


#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration Handshake
# Check for custom settings, fallback to template if missing
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


# Execution Phase
echo "[PROGRESS] Initializing Layer 1: Base Environment..."
bash "${BOOTSTRAP_DIR}/scripts/00_base_setup.sh"

echo "[SUCCESS] Layer 1 Provisioning Complete."
