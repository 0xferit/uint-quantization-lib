#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_DIR="${ROOT_DIR}/.kontrol"
IMAGE="${KONTROL_DOCKER_IMAGE:-runtimeverificationinc/kontrol:ubuntu-jammy-1.0.231}"
USE_BOOSTER="${KONTROL_USE_BOOSTER:-0}"
CONFIG_FILE="${KONTROL_CONFIG_FILE:-kontrol.toml}"
CONFIG_PROFILE="${KONTROL_CONFIG_PROFILE:-local-max}"

usage() {
  cat <<'EOF'
Usage: ./script/kontrol.sh <command>

Commands:
  prove-core    Build and prove Solidity-focused Kontrol specs.
  prove-parity  Build and prove Solidity + Vyper parity specs.
  list          List discovered Kontrol tests/specs.
  clean         Remove local Kontrol artifacts (.kontrol/).
EOF
}

docker_kontrol() {
  local cmd="$1"

  local -a run_args=(docker run --rm --user "$(id -u):$(id -g)")
  if [[ -t 1 ]]; then
    run_args+=(-t)
  fi
  run_args+=(-v "${ROOT_DIR}:${ROOT_DIR}" -w "${ROOT_DIR}" "${IMAGE}" bash -lc "${cmd}")
  "${run_args[@]}"
}

ensure_runtime() {
  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is unavailable. Start Docker and rerun the command." >&2
    exit 1
  fi
}

prove_matches() {
  local -a patterns=("$@")
  ensure_runtime
  mkdir -p "${ARTIFACT_DIR}"
  docker_kontrol "kontrol build --config-file ${CONFIG_FILE}"
  for pattern in "${patterns[@]}"; do
    local prove_cmd="kontrol prove --config-file ${CONFIG_FILE} --config-profile ${CONFIG_PROFILE} --match-test '${pattern}'"
    if [[ "${USE_BOOSTER}" != "1" ]]; then
      prove_cmd+=" --no-use-booster"
    fi
    docker_kontrol "${prove_cmd}"
  done
}

case "${1:-}" in
  prove-core)
    prove_matches \
      "ProofUintQuantizationSolidity.proof_*"
    ;;
  prove-parity)
    prove_matches \
      "ProofUintQuantizationSolidity.proof_*" \
      "ProofUintQuantizationVyper.proof_*"
    ;;
  list)
    ensure_runtime
    mkdir -p "${ARTIFACT_DIR}"
    mkdir -p "${ROOT_DIR}/out/proofs"
    docker_kontrol "kontrol build --config-file ${CONFIG_FILE}"
    docker_kontrol "kontrol list --config-file ${CONFIG_FILE}"
    ;;
  clean)
    rm -rf "${ARTIFACT_DIR}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
