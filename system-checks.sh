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

echo "==> Checking service"
kubectl -n "$NAMESPACE" get service "$RELEASE"

echo "==> Deployed image"
kubectl -n "$NAMESPACE" get deployment "$RELEASE" -o jsonpath='{.spec.template.spec.containers[0].image}'
echo

echo "==> Current pod status"
kubectl -n "$NAMESPACE" get pods -l app.kubernetes.io/instance="$RELEASE"

echo "==> Starting port-forward"
kubectl -n "$NAMESPACE" port-forward svc/"$RELEASE" "$LOCAL_PORT":80 >/tmp/skybyte-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!
trap 'kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true' EXIT

sleep 3

echo "==> Checking health endpoint"
curl --fail --silent --show-error "http://127.0.0.1:$LOCAL_PORT/healthz"
echo

echo "==> Checking metrics endpoint"
curl --fail --silent --show-error "http://127.0.0.1:$LOCAL_PORT/metrics" | grep "http_requests_total"

echo "==> System checks passed"
