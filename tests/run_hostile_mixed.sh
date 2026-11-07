#!/bin/bash
# run_hostile_mixed.sh -- like run_hostile.sh but only ONE argument position is hostile, the rest are 2.
# Output: perf_results/hostile_mixed.csv
cd "$(dirname "$0")"
HOST="../../raylib-miniscript/build-release/raylib-miniscript"
OUT=perf_results/hostile_mixed.csv
echo "method,pos,valueIdx,status,detail" > $OUT
"$HOST" perf_hostile.ms list 2>/dev/null | awk -F'\t' '/^[A-Za-z]+\.[a-zA-Z]/ && $2>=2 && $1 !~ /FromRaylib/ {print $1" "$2}' > perf_results/hostile_mixed_methods.txt
while read m np; do
  for pos in $(seq 0 $((np>4?3:np-1))); do
  for v in 0 1 2 3 4 5 6 7; do
    log=$(mktemp)
    "$HOST" perf_hostile.ms run "$m" $v $np $pos > "$log" 2>&1 &
    pid=$!; w=0
    while kill -0 $pid 2>/dev/null && [ $w -lt 100 ]; do sleep 0.1; w=$((w+1)); if grep -q "Runtime Error\|HOSTILE_OK" "$log"; then sleep 0.2; kill -9 $pid 2>/dev/null; break; fi; done
    if kill -0 $pid 2>/dev/null; then kill -9 $pid 2>/dev/null; fi
    wait $pid 2>/dev/null; rc=$?
    if grep -q "Runtime Error" "$log"; then echo "$m,$pos,$v,error,$(grep -m1 'Runtime Error' "$log" | tr ',' ';' | cut -c1-100)" >> $OUT
    elif grep -q HOSTILE_OK "$log"; then echo "$m,$pos,$v,ok," >> $OUT
    elif [ $rc -gt 128 ] && [ $rc -ne 137 ]; then echo "$m,$pos,$v,CRASH,rc=$rc" >> $OUT
    else echo "$m,$pos,$v,TIMEOUT," >> $OUT; fi
    rm $log
  done; done
done < perf_results/hostile_mixed_methods.txt
