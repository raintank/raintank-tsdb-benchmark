helps to easily stresstest a TSDB backend.

targets specifically metrics from env-load within a standard devstack with 1 collector.
make sure you have a good open file handles limit. see https://rtcamp.com/tutorials/linux/increase-open-files-limit/

1. install https://github.com/tsenart/vegeta
2. run standard dev-stack with one collector
3. run env-load. it defaults to 100 orgs
4. wait until all metrics exist (see graphite-watcher and sys dashboard)
5. ./run.sh 100
6. check results directory
