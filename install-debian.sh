#!/usr/bin/env bash
# Debian/Ubuntu system packages for mps-services-monitoring. Best-effort,
# sourced from install.sh; can also be run directly.
set -euo pipefail

SUDO=""
[[ ${EUID} -eq 0 ]] || SUDO="sudo"

# Toggles (defaults mirror the odem.services.monitoring role)
ENABLE_PACKAGES="${MPS_MONITORING_ENABLE_PACKAGES:-1}"
ENABLE_DOCKER="${MPS_MONITORING_ENABLE_DOCKER:-1}"

if [[ "${ENABLE_PACKAGES}" = 1 ]]; then
    # git + curl: clone/pull; openssl: Wazuh certificate generation
    ${SUDO} apt-get install -y git curl openssl
fi

if [[ "${ENABLE_DOCKER}" = 1 ]]; then
    if ! command -v docker >/dev/null 2>&1; then
        # docker.io + docker-compose (v2) from Debian; the odem stack normally
        # uses the official Docker repo via the odem.services.docker role.
        ${SUDO} apt-get install -y docker.io docker-compose \
            || echo "==> WARN: docker engine install failed"
    elif ! docker compose version >/dev/null 2>&1 \
         && ! command -v docker-compose >/dev/null 2>&1; then
        ${SUDO} apt-get install -y docker-compose \
            || echo "==> WARN: docker compose install failed"
    fi
fi

echo "mps-services-monitoring Debian packages installed"