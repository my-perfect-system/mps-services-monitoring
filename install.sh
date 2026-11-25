#!/usr/bin/env bash
# Install the mps-services-monitoring stack: OS packages (best-effort), .env
# seed, config files materialized from their .example siblings (only-if-absent),
# data-dir setup, optional Wazuh setup, then docker compose up (gated).
# Idempotent — mirrors the odem.services.monitoring role.
# OS-specific packages live in install-debian.sh / install-fedora.sh and are
# installed best-effort before the stack starts.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUDO=""
[[ ${EUID} -eq 0 ]] || SUDO="sudo"

#--- Distro detection -----------------------------------------------------------
detect_distro() {
    local id
    id="$(grep -sE '^ID=' /etc/os-release | head -1 | cut -d= -f2 | tr -d '\"')"
    case "${id}" in
        debian|ubuntu) echo "debian" ;;
        fedora|rhel)   echo "fedora" ;;
        *)
            if command -v apt-get >/dev/null 2>&1; then echo "debian"
            elif command -v dnf >/dev/null 2>&1; then echo "fedora"
            else echo "none"; fi ;;
    esac
}

#--- System: distro packages (best-effort) --------------------------------------
case "$(detect_distro)" in
    debian) "${SRC}/install-debian.sh" || echo "==> WARN: install-debian.sh failed; continuing" ;;
    fedora)  "${SRC}/install-fedora.sh" || echo "==> WARN: install-fedora.sh failed; continuing" ;;
    *)       echo "==> Unsupported distro — skipping system packages" ;;
esac

#--- .env — only-if-absent (local overrides are never clobbered) ----------------
if [[ ! -f "${SRC}/.env" ]]; then
    cp "${SRC}/.env.example" "${SRC}/.env"
    echo "==> Seeded ${SRC}/.env from .env.example"
fi

#--- Wazuh compose profile (toggle mirrors odem.services.monitoring
#    monitoring_enable_wazuh; default matches the role: off)
ENABLE_WAZUH="${MPS_MONITORING_ENABLE_WAZUH:-0}"
if [[ "${ENABLE_WAZUH}" = 1 ]]; then
    sed -i 's/^COMPOSE_PROFILES=.*/COMPOSE_PROFILES=wazuh/' "${SRC}/.env"
fi

#--- Config files from .example siblings — only-if-absent -----------------------
# (mirrors monitoring_config_files in the role; active configs are gitignored)
ensure_cfg() {
    if [[ ! -f "${SRC}/$2" ]]; then
        cp "${SRC}/$1" "${SRC}/$2"
    fi
}
ensure_cfg services/prometheus/prometheus.yml.example services/prometheus/prometheus.yml
ensure_cfg services/loki/loki-config.yml.example      services/loki/loki-config.yml
ensure_cfg services/grafana/grafana.ini.example      services/grafana/grafana.ini

#--- Data-dir setup (toggle mirrors monitoring_enable_setup) --------------------
ENABLE_SETUP="${MPS_MONITORING_ENABLE_SETUP:-1}"
if [[ "${ENABLE_SETUP}" = 1 ]]; then
    bash "${SRC}/scripts/setup.sh"
fi

#--- Wazuh one-time setup (certificates + vm.max_map_count) ---------------------
if [[ "${ENABLE_WAZUH}" = 1 && "${ENABLE_SETUP}" = 1 ]]; then
    bash "${SRC}/scripts/wazuh-setup.sh"
fi

#--- Compose stack (toggle mirrors monitoring_enable_service) -------------------
ENABLE_SERVICE="${MPS_MONITORING_ENABLE_SERVICE:-1}"
if [[ "${ENABLE_SERVICE}" = 1 ]]; then
    cd "${SRC}"
    if docker compose version >/dev/null 2>&1; then
        ${SUDO} docker compose up -d
    elif command -v docker-compose >/dev/null 2>&1; then
        ${SUDO} docker-compose up -d
    else
        echo "==> WARN: docker compose not found — install Docker + Compose, then run: docker compose up -d" >&2
    fi
fi

echo "mps-services-monitoring installed. Grafana: http://$(grep '^BIND_IP' "${SRC}/.env" | cut -d= -f2):3000 (default 127.0.0.1, admin/admin)."