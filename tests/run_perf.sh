#!/bin/bash
# run_perf.sh -- run Soda perf benchmarks: 3x un-profiled (timing, one CSV
# per run via a run-index arg) + 1x profiled (attribution).
# Usage: ./run_perf.sh [perf_soda.ms ...]   (defaults to all tests/perf_*.ms)
set -u
cd "$(dirname "$0")"

HOST="../../raylib-miniscript/build-release/raylib-miniscript"
mkdir -p perf_results

BENCHES=("$@")
if [ ${#BENCHES[@]} -eq 0 ]; then
	BENCHES=(perf_*.ms)
fi

# Runs one host invocation in the background, waits up to max_wait seconds
# for it to exit on its own (every perf_<unit>.ms must call perf.finish ->
# exit), and falls back to SIGINT then SIGKILL only if it hangs -- this is
# a safety net for a buggy benchmark, not the normal path.
run_one() {
	"$@" &
	local pid=$!
	local waited=0 max_wait=120
	while kill -0 "$pid" 2>/dev/null && [ $waited -lt $max_wait ]; do
		sleep 1; waited=$((waited+1))
	done
	if kill -0 "$pid" 2>/dev/null; then
		echo "  did not exit after ${max_wait}s; sending SIGINT" >&2
		kill -INT "$pid"; sleep 2
		if kill -0 "$pid" 2>/dev/null; then
			echo "  still alive; SIGKILL" >&2
			kill -9 "$pid"
		fi
	fi
	wait "$pid" 2>/dev/null
}

for script in "${BENCHES[@]}"; do
	name="${script%.ms}"
	for i in 1 2 3; do
		echo "== $script  run $i (un-profiled) =="
		run_one "$HOST" "$script" "$i"
	done
	echo "== $script  profiled =="
	run_one "$HOST" --profile "perf_results/${name}_profile" "$script" "profiled"
done
