#!/bin/bash
# run_hostile.sh -- drive perf_hostile.ms: one process per (method, hostile value).
# Output: perf_results/hostile.csv  (method,valueIdx,status,detail)  status: ok|error|CRASH|TIMEOUT
cd "$(dirname "$0")"
HOST="../../raylib-miniscript/build-release/raylib-miniscript"
OUT=perf_results/hostile.csv
echo "method,valueIdx,status,detail" > $OUT

while read m; do
  for v in 0 1 2 3 4 5 6 7; do
    log=$(mktemp)
    "$HOST" perf_hostile.ms run "$m" $v > "$log" 2>&1 &
    pid=$!
    w=0
    while kill -0 $pid 2>/dev/null && [ $w -lt 100 ]; do sleep 0.1; w=$((w+1)); if grep -q "Runtime Error\|HOSTILE_OK" "$log"; then sleep 0.2; kill -9 $pid 2>/dev/null; break; fi; done
    if kill -0 $pid 2>/dev/null; then kill -9 $pid 2>/dev/null; wait $pid 2>/dev/null; if ! grep -q "Runtime Error\|HOSTILE_OK" "$log"; then echo "$m,$v,TIMEOUT," >> $OUT; rm $log; continue; fi; fi
    wait $pid 2>/dev/null; rc=$?
    if grep -q "Runtime Error" "$log"; then rc=0; fi
    if grep -q HOSTILE_OK "$log"; then echo "$m,$v,ok," >> $OUT
    elif [ $rc -gt 127 ] || grep -qi 'segmentation\|bus error\|abort' "$log"; then echo "$m,$v,CRASH,rc=$rc" >> $OUT
    else echo "$m,$v,error,$(grep -m1 'Runtime Error\|Error' "$log" | tr ',' ';' | cut -c1-120)" >> $OUT; fi
    rm $log
  done
done < perf_results/hostile_methods.txt
