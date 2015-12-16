stresstest and measure performance of the TSDB backend of a raintank stack.

targets specifically metrics from env-load within a standard devstack with 1 collector.
make sure you have a good open file handles limit. see https://rtcamp.com/tutorials/linux/increase-open-files-limit/

# requirements

* https://github.com/tsenart/vegeta
* [raintank-docker](https://github.com/raintank/raintank-docker) aka devstack
* [graphite-watcher](https://github.com/raintank/raintank-metric/tree/tank/graphite-watcher)
* [env-load](https://github.com/raintank/env-load)

# how to

1. in devstack in grafana-dev/conf/custom.ini: alerting enabled false.
   alerting stresses grafana cpu too much, also sometimes the system can't keep up and it's hard to include that data in the results.
2. ./setup_dev.sh
3. ./launch_dev.sh
    runs standard dev-stack with one collector
4. verify measure, graphite-watcher, grafana are running in screen. login to grafana and check that sys dashboard works.
5. ./delay_collector.sh
6. rm logs/*
7. ./run.sh <config-file>  # see raintank-docker.conf as an example
8. when it completes, the results are only valid if:
   * the sys dashboard shows a lag <= something reasonable like 30s
   * run.sh/vegeta didn't show any errors, all requests were successfull.
   * graphite-watcher didn't error
   * graphite-api and cassandra didn't error
   * your host hard drive didn't run full, that tends to cause slowdowns
   * collector-controller didn't drop any checks/metrics
9. your data is in the results directory and in the grafana dashboards, take a snapshot.

# watch out for:
## high cpu due to wireless drivers
if i'm on wifi, even though everything should go through loopbacks,
a lot of cpu time is spent in iwlwifi kernel process, and in grafana/nsq_* processes that do a lot of network io (for redis, statsd, etc).
(can easily be confirmed with profiling). the solution is just disable wifi on the host
