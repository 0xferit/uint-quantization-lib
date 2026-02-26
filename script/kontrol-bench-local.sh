#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KONTROL_SCRIPT="${ROOT_DIR}/script/kontrol.sh"
CONFIG_FILE_NAME="$(basename "${KONTROL_CONFIG_FILE:-kontrol.toml}")"
LOCAL_PROFILE="${KONTROL_CONFIG_PROFILE:-local}"
LOCAL_HI_PROFILE="${KONTROL_LOCAL_HI_PROFILE:-local-hi}"

COMMAND="prove-core-hi"
SAMPLE_SECONDS=5
MIN_TOTAL_CPU=""

usage() {
  cat <<'EOF'
Usage: ./script/kontrol-bench-local.sh [options]

Options:
  --command <name>                One of: prove-core-hi, prove-parity-hi, prove-core, prove-parity
  --sample-seconds <n>            Sampling interval in seconds (default: 5)
  --require-min-total-cpu <pct>   Minimum average total CPU percentage required (e.g. 50)
  -h, --help                      Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --command)
      COMMAND="${2:-}"
      shift 2
      ;;
    --sample-seconds)
      SAMPLE_SECONDS="${2:-}"
      shift 2
      ;;
    --require-min-total-cpu)
      MIN_TOTAL_CPU="${2:-}"
      shift 2
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

case "${COMMAND}" in
  prove-core-hi|prove-parity-hi)
    PROFILE="${LOCAL_HI_PROFILE}"
    ;;
  prove-core|prove-parity)
    PROFILE="${LOCAL_PROFILE}"
    ;;
  *)
    echo "Unsupported --command value: ${COMMAND}" >&2
    exit 1
    ;;
esac

if ! [[ "${SAMPLE_SECONDS}" =~ ^[0-9]+$ ]] || [[ "${SAMPLE_SECONDS}" -eq 0 ]]; then
  echo "--sample-seconds must be a positive integer." >&2
  exit 1
fi

if [[ -n "${MIN_TOTAL_CPU}" ]] && ! [[ "${MIN_TOTAL_CPU}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "--require-min-total-cpu must be a number." >&2
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

cd "${ROOT_DIR}"
mkdir -p .kontrol

if ps -axo command= | rg "kontrol prove --config-file ${CONFIG_FILE_NAME} --config-profile ${PROFILE}" | rg -v rg >/dev/null; then
  echo "Another local Kontrol prove process is already running for profile '${PROFILE}'. Stop it first." >&2
  exit 1
fi

stamp="$(date +%Y%m%d-%H%M%S)"
log_file=".kontrol/bench-${COMMAND}-${stamp}.log"
csv_file=".kontrol/bench-${COMMAND}-${stamp}.csv"
cpus="$(logical_cpus)"

echo "timestamp,sum_pcpu,total_pct" > "${csv_file}"

"${KONTROL_SCRIPT}" "${COMMAND}" > "${log_file}" 2>&1 &
run_pid=$!

peak_total=0
sum_total=0
samples=0

while kill -0 "${run_pid}" 2>/dev/null; do
  now="$(date +%s)"
  sum_pcpu="$(sum_profile_pcpu)"
  total_pct="$(awk -v s="${sum_pcpu}" -v c="${cpus}" 'BEGIN { printf "%.2f", s / c }')"

  echo "${now},${sum_pcpu},${total_pct}" >> "${csv_file}"

  peak_total="$(awk -v a="${peak_total}" -v b="${total_pct}" 'BEGIN { if (b > a) print b; else print a }')"
  sum_total="$(awk -v a="${sum_total}" -v b="${total_pct}" 'BEGIN { print a + b }')"
  samples=$((samples + 1))

  sleep "${SAMPLE_SECONDS}"
done

set +e
wait "${run_pid}"
run_exit=$?
set -e

avg_total="$(awk -v s="${sum_total}" -v n="${samples}" 'BEGIN { if (n == 0) print 0; else printf "%.2f", s / n }')"

echo "benchmark_command=${COMMAND}"
echo "profile=${PROFILE}"
echo "logical_cpus=${cpus}"
echo "samples=${samples}"
echo "peak_total_pct=${peak_total}"
echo "avg_total_pct=${avg_total}"
echo "run_exit_code=${run_exit}"
echo "log_file=${log_file}"
echo "csv_file=${csv_file}"

if [[ "${run_exit}" -ne 0 ]]; then
  exit "${run_exit}"
fi

if [[ -n "${MIN_TOTAL_CPU}" ]]; then
  if awk -v avg="${avg_total}" -v min="${MIN_TOTAL_CPU}" 'BEGIN { exit !(avg < min) }'; then
    echo "Average total CPU ${avg_total}% is below required minimum ${MIN_TOTAL_CPU}%." >&2
    exit 3
  fi
fi
