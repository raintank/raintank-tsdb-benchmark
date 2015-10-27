#!/bin/bash

orgs=$1
HOST=$2
RATE_HIGH=$3
RATE_LOW=$4

if [ -z "$orgs" ]; then
  echo "specify number of orgs as \$1" >&1
  exit 2
fi

if [ -z "$HOST" ]; then
  HOST=localhost
fi

if [ -z "$RATE_HIGH" ]; then
  RATE_HIGH=50
fi

if [ -z "$RATE_LOW" ]; then
  RATE_LOW=50
fi


function targets () {
  local range=$1
  for org in $(seq 1 $orgs); do
    oid=$(($org +1))  # the id in mysql is the number + 1, because we start out with id 1 for master account.
    for endp in {1..4}; do
      sed -e "s#^#GET http://$HOST:8888/render?target=#" -e "s#\$org#$org#" -e "s#\$endp#$endp#" -e "s#\$#\&from=-$range\nX-Org-Id: $oid\n#" env-load-metrics-patterns.txt
    done
  done
}

function postEvent() {
  curl -X POST "$HOST:8086/db/raintank/series?u=graphite&p=graphite" -d '[{"name": "events","columns": ["type","tags","text"],"points": [['"\"$1\", \"$2\",\"$3\"]]}]"
}

function runTest () {
  local key=$1
  local range=$2
  local duration=$3
  local rate=$4
  f="results/$key-$range-$duration-$rate"


  desc="$key - time range: $range - duration: $duration - rate: $rate"

  echo "################## $(date): $desc START ###################"
  postEvent "bench-start" "" "benchmark $desc"
  vegeta attack -duration $duration -rate $rate > $f.bin
  cat $f.bin | vegeta report > $f.txt
  cat $f.bin | vegeta report -reporter="hist[0,50ms,100ms,200ms,400ms,750ms,1000ms,1500ms,2500ms,5000ms]" >> $f.txt
  cat $f.bin | vegeta report -reporter=plot > $f.html
  echo "################## $(date): $desc DONE ###################"
  postEvent "bench-stop" "" "benchmark $desc"
}

# waits until the clock is a nice round number, divisible by $2 seconds, at least $1 seconds or more in the future.
function waitTimeBoundary() {
  local minGap=$1
  local boundary=$2
  now=$(date +%s)
  nextMark=$(( $(( $(date -d "+ "$((minGap + boundary))" seconds" +%s) / $boundary)) * $boundary))
  diff=$(($nextMark - $now))
  echo waiting $diff seconds
  sleep $diff
}

postEvent "env-load start" "" "env-load loading $orgs orgs"
#env-load -orgs $orgs -host http://$HOST/ -monhost raintankdocker_grafana_1 load
postEvent "env-load finished" "" "env-load loaded $orgs orgs"

total=$(($orgs * 4 * 30))
echo "waiting for $orgs (orgs) * 4 (endpoints per org) * 30 = $total metrics to show up in ES... (see also sys dashboard)"
echo "this shouldn't take more than a minute.."
num=0
while true; do
  num=$(wget --quiet -O - "http://$HOST:8086/db/raintank/series?p=graphite&q=select+last(value)+from+%22graphite-watcher.num_metrics%22+where+time+%3E+now()-5m+order+asc&u=graphite" | sed -e 's#.*,##' -e 's#].*##')
  [ $num -eq $total ] && break
  echo "$(date) $num metrics..."
  sleep 10
done
echo "$(date) $num metrics!"


waitTimeBoundary 0 60
targets 5min | head -n 3 | runTest "min-diversity" 5min 180s $RATE_HIGH

waitTimeBoundary 20 60
targets 5min | runTest "max-diversity" 5min 180s $RATE_HIGH

waitTimeBoundary 20 60
targets 1h | head -n 3 | runTest "min-diversity" 1h 180s $RATE_HIGH

waitTimeBoundary 20 60
targets 1h | runTest "max-diversity" 1h 180s $RATE_LOW

waitTimeBoundary 20 60
targets 24h | head -n 3 | runTest "min-diversity" 24h 180s $RATE_LOW

waitTimeBoundary 20 60
targets 24h | runTest "max-diversity" 24h 180s $RATE_LOW

