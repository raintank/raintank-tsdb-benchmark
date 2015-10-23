#!/bin/bash
echo "run this first: ./env-load -auth admin:admin -orgs 100 load"

echo "creating list of all metrics you should have after an env-load with 100 orgs, 4 endpoints each, using dev-stack with 1 standard collector"

fulllist=$(mktemp)
for org in {1..100}; do
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

  echo "################## $1, $range time range. test duration: $duration ###################"
  sed "s#^#GET http://localhost:8888/render?target=\&from=-$span=#" | vegeta attack -duration 60s -rate 2000 > $f.bin
  cat $f.bin | vegeta report
  cat $f.bin | vegeta report -reporter="hist[0,100ms,200ms,300ms]"
  cat $f.bin | vegeta report -reporter=plot > $f.html
}

# waits until the clock is a nice round number, divisible by 10 minutes
function waitTimeBoundary() {
  now=$(date +%s)
  nextMark=$(( $(( $(date -d '+ 10 minutes' +%s) / 600)) * 600))
  diff=$(($nextMark - $now))
  echo sleeping $diff
  #sleep $diff
}

waitTimeBoundary
head -n 1 $fulllist | runTest "min-diversity" 24h 60s
waitTimeBoundary
cat $fulllist | runTest "max-diversity" 24h 60s
