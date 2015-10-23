#!/bin/bash

orgs=$1

if [ -z "$orgs" ]; then
  echo "specify number of orgs as \$1" >&1
  exit 2
fi

fulllist=$(mktemp)
for org in $(seq 1 $orgs); do
  for endp in {1..4}; do
    cat env-load-metrics-patterns.txt | sed -e "s#\$org#$org#" -e "s#\$endp#$endp#" >> $fulllist
  done
done

echo "list is at $fulllist -- it is $(wc -l $fulllist) lines long"

function runTest () {
  local key=$1
  local range=$2
  local duration=$3
  f="results/$key-$range-$duration"

  waitTimeBoundary

  echo "################## $(date): $1, $range time range. test duration: $duration START ###################"
  sed "s#^#GET http://localhost:8888/render?target=\&from=-$span=#" | vegeta attack -duration 60s -rate 2000 > $f.bin
  cat $f.bin | vegeta report
  cat $f.bin | vegeta report -reporter="hist[0,100ms,200ms,300ms]"
  cat $f.bin | vegeta report -reporter=plot > $f.html
  echo "################## $(date): $1, $range time range. test duration: $duration DONE ###################"
}

# waits until the clock is a nice round number, divisible by 10 minutes, at least 10 or more minutes in the future.
function waitTimeBoundary() {
  now=$(date +%s)
  #nextMark=$(( $(( $(date -d '+ 20 minutes' +%s) / 600)) * 600))
  nextMark=$(( $(( $(date -d '+ 2 minutes' +%s) / 60)) * 60))
  diff=$(($nextMark - $now))
  echo waiting $diff seconds for next test...
  sleep $diff
}

head -n 1 $fulllist | runTest "min-diversity" 5min 60s
cat $fulllist | runTest "max-diversity" 5min 60s

head -n 1 $fulllist | runTest "min-diversity" 1h 60s
cat $fulllist | runTest "max-diversity" 1h 60s

head -n 1 $fulllist | runTest "min-diversity" 24h 60s
cat $fulllist | runTest "max-diversity" 24h 60s

