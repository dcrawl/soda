#!/bin/bash
# run_scn_profiles.sh -- MiniScript profile + native xctrace profile for scenarios given as args (sequential, nothing else running).
cd "$(dirname "$0")"
H=../../raylib-miniscript/build-profile/raylib-miniscript
for n in "$@"; do
  $H --profile perf_results/scn${n}_profile perf_scenarios.ms prof$n $n > perf_results/scn${n}_profile.log 2>&1
  rm -rf perf_results/xctrace/scn$n.trace
  xcrun xctrace record --template 'Time Profiler' --output perf_results/xctrace/scn$n.trace --time-limit 60s --no-prompt --launch -- $H perf_scenarios.ms xt$n $n > perf_results/xctrace/scn$n.log 2>&1
  xcrun xctrace export --input perf_results/xctrace/scn$n.trace --xpath '/trace-toc/run[1]/data/table[@schema="time-profile"]' > perf_results/xctrace/scn$n.xml 2>/dev/null
  python3 analyze_trace.py perf_results/xctrace/scn$n.xml 40 > perf_results/xctrace/scn${n}_summary.txt
  rm -rf perf_results/xctrace/scn$n.trace perf_results/xctrace/scn$n.xml
  rm -f perf_results/perf_scenarios.runprof$n.csv perf_results/perf_scenarios.runxt$n.csv
  echo "done $n"
done
echo ALLDONE
