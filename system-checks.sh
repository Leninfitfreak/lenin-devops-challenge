#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${NAMESPACE:-devops-challenge}"
RELEASE="${RELEASE:-skybyte-app}"
LOCAL_PORT="${LOCAL_PORT:-18080}"

echo "==> Checking namespace"
kubectl get namespace "$NAMESPACE"

echo "==> Checking deployment"
kubectl -n "$NAMESPACE" get deployment "$RELEASE"

echo "==> Waiting for rollout"
kubectl -n "$NAMESPACE" rollout status deployment/"$RELEASE" --timeout=180s

echo "==> Waiting for ready pod"
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod -l app.kubernetes.io/instance="$RELEASE" --timeout=180s

POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/instance="$RELEASE" -o jsonpath='{.items[0].metadata.name}')"

echo "==> Checking service"
kubectl -n "$NAMESPACE" get service "$RELEASE"

echo "==> Deployed image"
kubectl -n "$NAMESPACE" get deployment "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].image}'
echo

echo "==> Current pod status"
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/instance="$RELEASE"

echo "==> Runtime user"
UID_VALUE="$(kubectl -n "$NAMESPACE" exec "$POD" -- id -u)"
GID_VALUE="$(kubectl -n "$NAMESPACE" exec "$POD" -- id -g)"
echo "uid=$UID_VALUE gid=$GID_VALUE"
test "$UID_VALUE" != "0"

echo "==> Runtime capabilities"
CAP_EFF="$(kubectl -n "$NAMESPACE" exec "$POD" -- sh -c "awk '/^CapEff:/ {print \$2}' /proc/self/status")"
echo "CapEff=$CAP_EFF"
test "$CAP_EFF" = "0000000000000000"

echo "==> Listening port"
BOUND_PORT="$(kubectl -n "$NAMESPACE" exec "$POD" -- sh -c "awk '\$2 ~ /:1F90$/ && \$4 == \"0A\" {print \$2}' /proc/net/tcp /proc/net/tcp6 2>/dev/null | head -n 1")"
test -n "$BOUND_PORT"
echo "port=8080 socket=$BOUND_PORT"

echo "==> Starting port-forward"
kubectl -n "$NAMESPACE" port-forward svc/"$RELEASE" "$LOCAL_PORT":80 >/tmp/skybyte-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!
trap 'kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true' EXIT

sleep 3

echo "==> Checking application endpoint"
HTTP_STATUS="$(curl --silent --output /tmp/skybyte-response.txt --write-out "%{http_code}" "http://127.0.0.1:$LOCAL_PORT/")"
echo "HTTP $HTTP_STATUS"
test "$HTTP_STATUS" = "200"
grep "Hello, Candidate" /tmp/skybyte-response.txt

echo "==> Checking health endpoint"
curl --fail --silent --show-error "http://127.0.0.1:$LOCAL_PORT/healthz"
echo

echo "==> Checking metrics endpoint"
curl --fail --silent --show-error "http://127.0.0.1:$LOCAL_PORT/metrics" | grep "http_requests_total"

echo "==> Checking pod recovery"
kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
trap - EXIT
START_TIME="$(date +%s)"
kubectl -n "$NAMESPACE" delete pod "$POD"
kubectl -n "$NAMESPACE" wait --for=delete pod/"$POD" --timeout=30s
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod -l app.kubernetes.io/instance="$RELEASE" --timeout=30s
END_TIME="$(date +%s)"
echo "Recovered in $((END_TIME - START_TIME)) seconds"

echo "==> Recovered pod status"
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/instance="$RELEASE"

echo "==> Checking health after recovery"
kubectl -n "$NAMESPACE" port-forward svc/"$RELEASE" "$LOCAL_PORT":80 >/tmp/skybyte-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!
trap 'kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true' EXIT
sleep 3
curl --fail --silent --show-error "http://127.0.0.1:$LOCAL_PORT/healthz"
echo

echo "==> System checks passed"
