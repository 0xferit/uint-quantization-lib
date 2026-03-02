#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/.kontrol"
CONFIG_FILE="${KONTROL_CONFIG_FILE:-kontrol.toml}"
CONFIG_PROFILE="${KONTROL_CONFIG_PROFILE:-local}"
KONTROL_BIN="${KONTROL_BIN:-kontrol}"

usage() {
  cat <<'EOF'
Usage: ./script/kontrol.sh <command>

Commands:
  list   List discovered Kontrol tests/specs.
  clean  Remove local Kontrol artifacts (.kontrol/).
EOF
}

run_kontrol() {
  "${KONTROL_BIN}" "$@"
}

ensure_runtime() {
  if ! command -v "${KONTROL_BIN}" >/dev/null 2>&1; then
    cat >&2 <<EOF
Kontrol is not installed locally.
Install locally (Apple Silicon):
  APPLE_SILICON=true UV_PYTHON=3.10 kup install kontrol --version v1.0.231
EOF
    exit 1
  fi

  if ! command -v forge >/dev/null 2>&1; then
    echo "Foundry (forge) is required but not installed." >&2
    exit 1
  fi

}

write_toolchain_metadata() {
  mkdir -p "${ARTIFACT_DIR}"
  {
    printf 'timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'kontrol_bin=%s\n' "$(command -v "${KONTROL_BIN}")"
    printf 'kontrol_version=%s\n' "$("${KONTROL_BIN}" version | tr '\n' ' ' | sed 's/[[:space:]]\+/ /g' | sed 's/[[:space:]]$//')"
    printf 'forge_version=%s\n' "$(forge --version | head -n 1)"
  } > "${ARTIFACT_DIR}/local-toolchain.txt"
}

case "${1:-}" in
  list)
    cd "${ROOT_DIR}"
    ensure_runtime
    write_toolchain_metadata
    mkdir -p "${ROOT_DIR}/out/proofs"
    run_kontrol build --config-file "${CONFIG_FILE}" --config-profile "${CONFIG_PROFILE}"
    run_kontrol list --config-file "${CONFIG_FILE}"
    ;;
  clean)
    rm -rf "${ARTIFACT_DIR}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
