#!/bin/bash

function die_error () {
	echo "$@" >&2
	exit 2
}

[ -n "$1" -a -r "$1" ] || die_error "arg1 must be a readable config file"
source "$1" || die_error "can't read config file"

[ -n "$orgs" ] || die_error 'need $orgs number of orgs'
[ -n "$graphite_host" ] || die_error 'need $graphite_host'
[ -n "$graphitemon_host" ] || die_error 'need $graphitemon_host'
[ -n "$grafana_host" ] || die_error 'need $grafana_host'
[ -n "$elasticsearch_host" ] || die_error 'need $elasticsearch_host'
[ -n "$mon_host" ] || die_error 'need $mon_host'
[ -n "$env" ] || die_error 'need $env'
[ -n "$rate_high" ] || die_error 'need $rate_high'
[ -n "$rate_low" ] || die_error 'need $rate_low'


function metriclist () {
  for org in $(seq 1 $orgs); do
    for endp in {1..4}; do
	    sed -e "s#\$org#$org#" -e "s#\$endp#$endp#" env-load-metrics-patterns.txt | egrep -v 'dns.(ttl|answers|default|time)'
    done
  done
}

function targets () {
  local range=$1
  for org in $(seq 1 $orgs); do
    oid=$(($org +1))  # the id in mysql is the number + 1, because we start out with id 1 for master account.
    for endp in {1..4}; do
	      egrep -v 'dns.(ttl|answers|default|time)' env-load-metrics-patterns.txt | \
      sed -e "s#^#GET http://$graphite_host:8888/render?target=#" -e "s#\$org#$org#" -e "s#\$endp#$endp#" -e "s#\$#\&from=-$range\nX-Org-Id: $oid\n#"
    done
  done
}

function postEvent() {
  D=$(( $(date +%s) * 1000))
  payload='{"timestamp": '$D',"type": "'$1'","tags": "'$2'","text": "'$3'"}'
  curl -X POST "$elasticsearch_host:9200/benchmark/event?" -d "$payload" >/dev/null
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

cur_orgs=$(env-load -host http://$grafana_host/ status 2>/dev/null | awk '/fake_user/ {print $2}' | sort | uniq | wc -l)
if [ "$orgs" -ne "$cur_orgs" ]; then
  [ "$orgs" -gt 0 ] && env-load -host http://$grafana_host/ clean
  postEvent "env-load start" "" "env-load loading $orgs orgs"
  env-load -orgs $orgs -host http://$grafana_host/ -monhost $mon_host load
  postEvent "env-load finished" "" "env-load loaded $orgs orgs"
fi

metriclist > results/metriclist.txt
echo "all the metrics should be in results/metriclist.txt, use inspect-es to compare"

total=$(($orgs * 4 * 26))
echo "waiting for $orgs (orgs) * 4 (endpoints per org) * 26 = $total metrics to show up in ES... (see also sys dashboard)"
echo "this shouldn't take more than a minute.."
num=0
while true; do
  num=$(wget --quiet -O - "http://$graphitemon_host:8000/render/?target=graphite-watcher.$env.num_metrics&from=-2min&until=-10s&format=raw" | sed -e 's#.*,##')
  (( $(echo  "$num >=  $total"|bc -l) )) && break
  [ -z "$num" ] && echo "WARN: unable to parse proper graphite-watcher.$env.num_metrics value from graphite"
  echo "$(date) $num/$total metrics..."
  sleep 10
done
echo "$(date) $num metrics!"


waitTimeBoundary 0 60
targets 5min | head -n 3 | runTest "min-diversity" 5min 180s $rate_high

waitTimeBoundary 20 60
targets 5min | runTest "max-diversity" 5min 180s $rate_high

waitTimeBoundary 20 60
targets 1h | head -n 3 | runTest "min-diversity" 1h 180s $rate_low

waitTimeBoundary 20 60
targets 1h | runTest "max-diversity" 1h 180s $rate_low

waitTimeBoundary 20 60
targets 24h | head -n 3 | runTest "min-diversity" 24h 180s $rate_low

waitTimeBoundary 20 60
targets 24h | runTest "max-diversity" 24h 180s $rate_low

