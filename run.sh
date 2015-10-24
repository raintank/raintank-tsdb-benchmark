#!/bin/bash

orgs=$1

if [ -z "$orgs" ]; then
  echo "specify number of orgs as \$1" >&1
  exit 2
fi

function writePatterns () {
  fulllist=$(mktemp)
  for org in $(seq 1 $orgs); do
    oid=$(($org +1))  # the id in mysql is the number + 1, because we start out with id 1 for master account.
    for endp in {1..4}; do
      cat env-load-metrics-patterns.txt | sed -e "s#\$org#$org#" -e "s#\$endp#$endp#" -e "s#\$#\nX-Org-Id: $oid\n#" >> $fulllist
    done
  done
}

function postEvent() {
  curl -X POST "localhost:8086/db/raintank/series?u=graphite&p=graphite" -d '[{"name": "events","columns": ["type","tags","text"],"points": [['"\"$1\", \"$2\",\"$3\"]]}]"
}

function runTest () {
  local key=$1
  local range=$2
  local duration=$3
  local rate=$4
  f="results/$key-$range-$duration-$rate"

  waitTimeBoundary 1

  desc="$key - time range: $range - duration: $duration - rate: $rate"

  echo "################## $(date): $desc START ###################"
  postEvent "bench-start" "" "benchmark $desc"
  sed "s#^#GET http://localhost:8888/render?target=\&from=-$span=#" | vegeta attack -duration 60s -rate $rate > $f.bin
  cat $f.bin | vegeta report > $f.txt
  cat $f.bin | vegeta report -reporter="hist[0,100ms,200ms,300ms]" >> $f.txt
  cat $f.bin | vegeta report -reporter=plot > $f.html
  echo "################## $(date): $1, $range time range. test duration: $duration DONE ###################"
  postEvent "bench-stop" "" "benchmark $desc"
}

# for an arg of e.g. 10 minutes,
# waits until the clock is a nice round number, divisible by 10 minutes, at least 10 or more minutes in the future.
# so between 10 and 20 minutes from now.
function waitTimeBoundary() {
  local minutes=$1
  local seconds=$((minutes * 60))
  local twiceMinutes=$(($minutes * 2))
  now=$(date +%s)
  nextMark=$(( $(( $(date -d "+ $twiceMinutes minutes" +%s) / $seconds)) * $seconds))
  diff=$(($nextMark - $now))
  echo waiting $diff seconds
  sleep $diff
}

#waitTimeBoundary 1
postEvent "env-load start" "" "env-load loading $orgs orgs"
env-load -orgs $orgs load
postEvent "env-load finished" "" "env-load loaded $orgs orgs"
writePatterns

echo "please wait for $orgs (orgs) * 4 (endpoints per org) * 30 = $(($orgs * 4 * 30)) metrics to show up in ES (see sys dashboard)"
echo "press a key to proceed when ready"
read
echo "continuing..."

head -n 3 $fulllist | runTest "min-diversity" 5min 180s 200
cat $fulllist | runTest "max-diversity" 5min 180s 200

head -n 3 $fulllist | runTest "min-diversity" 1h 180s 100
cat $fulllist | runTest "max-diversity" 1h 180s 100

head -n 3 $fulllist | runTest "min-diversity" 24h 180s 100
cat $fulllist | runTest "max-diversity" 24h 180s 100

