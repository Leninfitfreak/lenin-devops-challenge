#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
IMAGE="skybyte/app:${IMAGE_TAG}"
NAMESPACE="${NAMESPACE:-devops-challenge}"

if [ -z "${TF_VAR_api_token:-}" ]; then
  echo "TF_VAR_api_token is required"
  exit 1
fi

echo "==> Building Docker image"
docker build -t "$IMAGE" .

if command -v kind >/dev/null 2>&1 && kind get clusters | grep -qx "skybyte-devops"; then
  echo "==> Loading Docker image into Kind"
  kind load docker-image "$IMAGE" --name skybyte-devops
fi

echo "==> Applying Terraform"
cd terraform
terraform init
terraform apply -auto-approve
cd ..

echo "==> Applying Kyverno policies"
kubectl apply -f policies/

echo "==> Installing Helm chart"
helm upgrade --install skybyte-app helm/skybyte-app \
  --namespace "$NAMESPACE" \
  --set image.tag="$IMAGE_TAG"

echo "==> Done"
