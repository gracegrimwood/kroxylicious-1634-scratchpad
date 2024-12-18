#!/bin/sh

EXEC_START_TIME=$(date +%s)

KROXY_NS="${KROXY_NS:-"kroxylicious"}"
KROXY_DIR="${KROXY_DIR:-"kroxylicious"}"
KROXY_DEPL_NAME="${KROXY_DEPL_NAME:-"kroxylicious-proxy"}"

TESTER_NS="${TESTER_NS:-"kroxytest"}"
TESTER_DIR="${TESTER_DIR:-"kroxytester"}"
TESTER_DEPL_NAME="${TESTER_DEPL_NAME:-"kroxytester"}"
TESTER_POD_NUM=5

DEPL_DEFAULT="${DEPL_DEFAULT:-"defaults"}"
DEPL_APP_DEBUG="${DEPL_APP_DEBUG:-"APP-DEBUG"}"
DEPL_ROOT_DEBUG="${DEPL_ROOT_DEBUG:-"ROOT-DEBUG"}"
DEPL_REPLICAS="${DEPL_REPLICAS:-"repl"}"
DEPL_EXT="${DEPL_EXT:-"yaml"}"

KROXY_DEFAULT_DEPL="$(printf "%s/%s_%s_%d%s.%s" "${KROXY_DIR}" "${KROXY_DEPL_NAME}" "${DEPL_DEFAULT}" 0 "${DEPL_REPLICAS}" "${DEPL_EXT}")"
TESTER_DEFAULT_DEPL="$(printf "%s/%s_%s_%d%s.%s" "${TESTER_DIR}" "${TESTER_DEPL_NAME}" "${DEPL_DEFAULT}" 0 "${DEPL_REPLICAS}" "${DEPL_EXT}")"

# reset to defaults
oc apply -n "${TESTER_NS}" -f "${TESTER_DEFAULT_DEPL}"
oc apply -n "${KROXY_NS}" -f "${KROXY_DEFAULT_DEPL}"

# START
KROXY_ROOT_DEBUG_DEPL="$(printf "%s/%s_%s_%d%s.%s" "${KROXY_DIR}" "${KROXY_DEPL_NAME}" "${DEPL_ROOT_DEBUG}" 1 "${DEPL_REPLICAS}" "${DEPL_EXT}")"
TESTER_LOAD_DEPL="$(printf "%s/%s_%s_%d%s.%s" "${TESTER_DIR}" "${TESTER_DEPL_NAME}" "${DEPL_DEFAULT}" $TESTER_POD_NUM "${DEPL_REPLICAS}" "${DEPL_EXT}")"

printf "Kroxylicious load test starting at %s\n" "$(date -jf "%s" "${EXEC_START_TIME}" +"%Y-%m-%dT%H:%M:%S")"

oc apply -n "${KROXY_NS}" -f "${KROXY_ROOT_DEBUG_DEPL}"

sleep 10

KROXY_POD=$(oc get pods -n "${KROXY_NS}" -o name | sed 's/pod\///g')
oc logs -n "${KROXY_NS}" "${KROXY_POD}" -f > "logs/$(date -jf "%s" "${EXEC_START_TIME}" +"%Y%m%d_%H%M%S")_${KROXY_POD}.log" &

oc apply -n "${TESTER_NS}" -f "${TESTER_LOAD_DEPL}"
oc wait --for=condition=Ready -n "${TESTER_NS}" "deploy/${TESTER_DEPL_NAME}" --timeout=30s

oc get pods -n "${TESTER_NS}" -o name | sed 's/pod\///g' | while read -r TESTER_POD; do
    oc logs -n "${TESTER_NS}" "${TESTER_POD}" -f > "logs/$(date -jf "%s" "${EXEC_START_TIME}" +"%Y%m%d_%H%M%S")_${TESTER_POD}.log" &
done

sleep 140

# reset to defaults
oc apply -n "${TESTER_NS}" -f "${TESTER_DEFAULT_DEPL}"

sleep 30

oc apply -n "${KROXY_NS}" -f "${KROXY_DEFAULT_DEPL}"
