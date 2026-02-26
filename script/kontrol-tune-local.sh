#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${KONTROL_CONFIG_FILE:-kontrol.toml}"
CONFIG_FILE_NAME="$(basename "${CONFIG_FILE}")"
PROFILE="${KONTROL_LOCAL_HI_PROFILE:-local-hi}"
KONTROL_BIN="${KONTROL_BIN:-kontrol}"

MATCH_TEST="ProofUintQuantizationSolidity.prove_.*target_bits_256_reverts.*"
SAMPLE_SECONDS=5
PROBE_SECONDS=300
MIN_TOTAL_CPU=7
INCLUDE_BOOSTER=0
REINIT=1

usage() {
  cat <<'EOF'
Usage: ./script/kontrol-tune-local.sh [options]

Options:
  --match-test <pattern>     Kontrol --match-test pattern (default: essential Solidity subset)
  --sample-seconds <n>       Sampling interval in seconds (default: 5)
  --probe-seconds <n>        Max runtime per candidate probe in seconds (default: 300)
  --min-total-cpu <pct>      Required average total CPU percentage (default: 7)
  --include-booster          Include booster-enabled candidates
  --no-reinit                Reuse existing proofs (default is --reinit)
  -h, --help                 Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --match-test)
      MATCH_TEST="${2:-}"
      shift 2
      ;;
    --sample-seconds)
      SAMPLE_SECONDS="${2:-}"
      shift 2
      ;;
    --probe-seconds)
      PROBE_SECONDS="${2:-}"
      shift 2
      ;;
    --min-total-cpu)
      MIN_TOTAL_CPU="${2:-}"
      shift 2
      ;;
    --include-booster)
      INCLUDE_BOOSTER=1
      shift
      ;;
    --no-reinit)
      REINIT=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "${SAMPLE_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${SAMPLE_SECONDS}" -eq 0 ]]; then
  echo "--sample-seconds must be a positive integer." >&2
  exit 1
fi
if ! [[ "${PROBE_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${PROBE_SECONDS}" -eq 0 ]]; then
  echo "--probe-seconds must be a positive integer." >&2
  exit 1
fi
if ! [[ "${MIN_TOTAL_CPU}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "--min-total-cpu must be a number." >&2
  exit 1
fi

logical_cpus() {
  getconf _NPROCESSORS_ONLN
}

sum_profile_pcpu() {
  ps -axo pcpu=,command= \
    | awk -v marker="kontrol prove --config-file ${CONFIG_FILE_NAME} --config-profile ${PROFILE}" '
        index($0, marker) || index($0, "kore-rpc out/kompiled/definition.kore") || index($0, "kore-rpc-booster") { sum += $1 }
        END { printf "%.1f", sum + 0 }
      '
}

kill_profile_processes() {
  ps -axo pid=,command= \
    | rg "kontrol prove --config-file ${CONFIG_FILE_NAME} --config-profile ${PROFILE}" \
    | rg -v rg \
    | awk '{print $1}' \
    | xargs -n1 kill >/dev/null 2>&1 || true
}

run_probe() {
  local label="$1"
  local args_string="$2"

  local log_file=".kontrol/tune-${label}.log"
  local start now elapsed sum_pcpu total_pct
  local peak_total=0
  local sum_total=0
  local samples=0
  local run_exit=0

  # shellcheck disable=SC2206
  local extra_args=( ${args_string} )

  if [[ "${REINIT}" -eq 1 ]]; then
    extra_args=( --reinit "${extra_args[@]}" )
  fi
  "${KONTROL_BIN}" prove \
    --config-file "${CONFIG_FILE}" \
    --config-profile "${PROFILE}" \
    --match-test "${MATCH_TEST}" \
    "${extra_args[@]}" > "${log_file}" 2>&1 &
  local run_pid=$!
  start="$(date +%s)"

  while kill -0 "${run_pid}" 2>/dev/null; do
    now="$(date +%s)"
    elapsed=$((now - start))
    if (( elapsed >= PROBE_SECONDS )); then
      kill "${run_pid}" >/dev/null 2>&1 || true
      break
    fi

    sum_pcpu="$(sum_profile_pcpu)"
    total_pct="$(awk -v s="${sum_pcpu}" -v c="${CPUS}" 'BEGIN { printf "%.2f", s / c }')"
    peak_total="$(awk -v a="${peak_total}" -v b="${total_pct}" 'BEGIN { if (b > a) print b; else print a }')"
    sum_total="$(awk -v a="${sum_total}" -v b="${total_pct}" 'BEGIN { print a + b }')"
    samples=$((samples + 1))
    sleep "${SAMPLE_SECONDS}"
  done

  set +e
  wait "${run_pid}"
  run_exit=$?
  set -e

  kill_profile_processes
  sleep 1

  now="$(date +%s)"
  elapsed=$((now - start))
  local avg_total
  avg_total="$(awk -v s="${sum_total}" -v n="${samples}" 'BEGIN { if (n == 0) print 0; else printf "%.2f", s / n }')"

  printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "${label}" "${samples}" "${peak_total}" "${avg_total}" "${elapsed}" "${run_exit}" "${args_string}" >> "${RESULTS_FILE}"

  echo "probe=${label} peak_total_pct=${peak_total} avg_total_pct=${avg_total} elapsed_s=${elapsed} exit_code=${run_exit}"
}

cd "${ROOT_DIR}"
mkdir -p .kontrol

if ps -axo command= | rg "kontrol prove --config-file ${CONFIG_FILE_NAME} --config-profile ${PROFILE}" | rg -v rg >/dev/null; then
  echo "Another local Kontrol prove process is running for profile '${PROFILE}'. Stop it first." >&2
  exit 1
fi

CPUS="$(logical_cpus)"
STAMP="$(date +%Y%m%d-%H%M%S)"
RESULTS_FILE=".kontrol/tune-results-${STAMP}.csv"
echo "label,samples,peak_total_pct,avg_total_pct,elapsed_seconds,exit_code,args" > "${RESULTS_FILE}"

"${KONTROL_BIN}" build --config-file "${CONFIG_FILE}" --config-profile "${PROFILE}" >/dev/null 2>&1

candidates=(
  "w8_f8|--workers 8 --max-frontier-parallel 8 --no-use-booster"
  "w12_f12|--workers 12 --max-frontier-parallel 12 --no-use-booster"
  "w16_f16|--workers 16 --max-frontier-parallel 16 --no-use-booster"
  "opt8|--optimize-performance 8 --no-use-booster"
  "opt12|--optimize-performance 12 --no-use-booster"
  "opt16|--optimize-performance 16 --no-use-booster"
)

if [[ "${INCLUDE_BOOSTER}" -eq 1 ]]; then
  candidates+=(
    "w8_f8_boost|--workers 8 --max-frontier-parallel 8 --use-booster"
    "w12_f12_boost|--workers 12 --max-frontier-parallel 12 --use-booster"
    "w16_f16_boost|--workers 16 --max-frontier-parallel 16 --use-booster"
  )
fi

for candidate in "${candidates[@]}"; do
  label="${candidate%%|*}"
  args="${candidate#*|}"
  run_probe "${label}" "${args}"
done

best_line="$(awk -F, -v min="${MIN_TOTAL_CPU}" '
  NR == 1 { next }
  $6 == 0 && $4 + 0 >= min {
    if (!seen || ($4 + 0) > best_avg || (($4 + 0) == best_avg && ($5 + 0) < best_elapsed)) {
      seen = 1
      best_avg = $4 + 0
      best_elapsed = $5 + 0
      best = $0
    }
  }
  END { if (seen) print best }
' "${RESULTS_FILE}")"

echo "results_file=${RESULTS_FILE}"

if [[ -z "${best_line}" ]]; then
  echo "No candidate met the required average total CPU threshold (${MIN_TOTAL_CPU}%)." >&2
  echo "Escalate to source-build track or relax constraints." >&2
  exit 4
fi

IFS=',' read -r best_label _ best_peak best_avg best_elapsed best_exit best_args <<< "${best_line}"

echo "best_label=${best_label}"
echo "best_peak_total_pct=${best_peak}"
echo "best_avg_total_pct=${best_avg}"
echo "best_elapsed_seconds=${best_elapsed}"
echo "best_exit_code=${best_exit}"
echo "best_args=${best_args}"
