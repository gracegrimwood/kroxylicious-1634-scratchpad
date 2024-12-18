#!/bin/sh

# Env vars. Set these in the deployment YAML for configurability.
# TOPIC="${TOPIC:-"kroxylicioustest"}"
# NUM_RECORDS="${NUM_RECORDS:-90000}"
# THROUGHPUT="${THROUGHPUT:-500}"
# BOOTSTRAP="${BOOTSTRAP:-"kroxylicious-service.kroxylicious.svc.cluster.local:30192"}"
# RECORD_SIZE="${RECORD_SIZE:-1000}"

EXEC_START_TIME=$(date +%s)

printf "Kroxytester started at %s\n" "$(date -d \@${EXEC_START_TIME} --iso-8601=seconds)"

/opt/kafka/bin/kafka-producer-perf-test.sh --topic "${TOPIC:-"kroxylicioustest"}" --num-records "${NUM_RECORDS:-90000}" --throughput "${THROUGHPUT:-500}" --producer-props "bootstrap.servers=${BOOTSTRAP:-"kroxylicious-service.kroxylicious.svc.cluster.local:30192"}" --record-size "${RECORD_SIZE:-1000}" --print-metrics

EXEC_END_TIME=$(date +%s)
EXEC_DURATION=$((EXEC_END_TIME - EXEC_START_TIME))

printf "Kroxytester finished at %s after %s seconds\n" "$(date -d \@${EXEC_END_TIME} --iso-8601=seconds)" "${EXEC_DURATION}"

# Loop until killed.
# This is so that the container does not self-terminate and get re-scheduled.

printf "Container will now idle until killed.\n"
LOOP_START_TIME=$(date +%s)

while true; do
    LOOP_DURATION=$(($(date +%s) - LOOP_START_TIME))
    if [ $LOOP_DURATION -ge 60 ]; then
        printf "Container has been idle since %s (%s).\n" "$(date -d \@${LOOP_START_TIME} --iso-8601=seconds)" "$((LOOP_DURATION / 60)) minutes, $((LOOP_DURATION % 60)) seconds"
    else
        printf "Container has been idle since %s (%s).\n" "$(date -d \@${LOOP_START_TIME} --iso-8601=seconds)" "${LOOP_DURATION} seconds"
    fi
    sleep 2s
done