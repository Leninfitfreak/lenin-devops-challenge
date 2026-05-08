# Skybyte API

A small Flask service that returns a greeting, exposes health and Prometheus-compatible metrics endpoints, and runs in Kubernetes through Docker, Terraform, Helm, and Kind-friendly local validation.

This repository is an incremental hardening pass over an inherited deployment. It keeps the app small while improving container hygiene, Kubernetes runtime controls, secret handling, CI validation, metrics, deterministic image tagging, admission policies, and post-deploy checks.

## Prerequisites

- Docker Desktop or another Docker engine
- Kind or another local Kubernetes cluster
- kubectl
- Helm 3.x
- Terraform 1.5+
- Python 3.9+
- Kyverno installed in the target cluster
- Kyverno CLI for local policy validation

## Quick Start

Create or select a Kubernetes cluster, then provide the application token for Terraform:

```bash
export TF_VAR_api_token="local-dev-token"
./setup.sh
./system-checks.sh
```

`setup.sh` requires `TF_VAR_api_token`, builds the Docker image, loads it into the `skybyte-devops` Kind cluster when that cluster exists, applies Terraform, applies Kyverno policies, and installs or upgrades the Helm release.

By default, the image tag is the current Git short SHA. Set `IMAGE_TAG` to deploy a specific tag:

```bash
IMAGE_TAG=1.0.0 ./setup.sh
```

## Deployment Flow

- Docker builds `skybyte/app:<tag>` from the Flask application.
- Terraform creates the `devops-challenge` namespace, runtime ResourceQuota, and `api-token` Secret.
- Kyverno policies are applied before the workload is installed.
- Helm deploys the Kubernetes Deployment and Service.
- Kind is used for local Kubernetes runtime validation and local image loading.
- Kubernetes runs the app with Gunicorn, non-root settings, probes, resource limits, and Prometheus scrape annotations.
- The container listens on port `8080`, while the Kubernetes Service exposes port `80`.

## Runtime Verification

Run the post-deploy validation script after `./setup.sh` or after a Helm upgrade:

```bash
./system-checks.sh
```

The script verifies:

- namespace
- deployment rollout
- ready pod
- service
- deployed image tag
- current pod status
- `/healthz`
- `/metrics`

Manual checks:

```bash
kubectl -n devops-challenge get pods
kubectl -n devops-challenge get deployment skybyte-app -o jsonpath='{.spec.template.spec.containers[0].image}'
kubectl -n devops-challenge port-forward svc/skybyte-app 8080:80
curl http://localhost:8080/
curl http://localhost:8080/healthz
curl http://localhost:8080/metrics
```

## Metrics

The app exposes:

- `GET /healthz`
- `GET /metrics`

Metrics include request count and request duration with `method`, `path`, and `status` labels. The pod template includes Prometheus scrape annotations for `/metrics` on port `8080`.

## Service Level Objective

99% of requests to `/` should complete in under 300 ms over a rolling 7-day window. This would be measured from `http_request_duration_seconds` once Prometheus scraping and alerting are installed; this repository exposes the metric but does not yet enforce the SLO.

## Admission Policies

Kyverno policies live in `policies/` and enforce the runtime standards already used by the chart:

- images must not use the `latest` tag
- workloads must run as non-root
- containers must declare CPU and memory requests and limits

Validate rendered manifests locally:

```bash
helm template skybyte-app helm/skybyte-app > rendered.yaml
kyverno apply policies/ -r rendered.yaml
```

`setup.sh` applies policies automatically during deployment. Apply them manually when validating policy changes outside the full deployment flow:

```bash
kubectl apply -f policies/
```

## CI Validation

GitHub Actions runs a single validation job on push and pull request. The workflow currently checks:

- Python dependency installation
- Python linting
- pytest
- Trivy filesystem vulnerability and secret scan
- Docker image build
- Helm lint
- Helm template rendering
- kubeconform validation for rendered manifests
- Terraform formatting
- Terraform validation

Extended CI checks such as buildx multi-arch builds, image scanning, and Kyverno policy checks are planned follow-up work.

## Runtime Hardening

The Helm chart configures:

- Gunicorn serving on container port `8080`
- Kubernetes Service exposing port `80`
- non-root pod and container execution
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- dropped Linux capabilities
- `RuntimeDefault` seccomp profile
- CPU and memory requests and limits
- namespace ResourceQuota for aggregate CPU and memory requests and limits
- readiness and liveness probes on `/healthz`
- `terminationGracePeriodSeconds: 30`

## Repository Layout

```text
/
|-- app/                  Flask service and tests
|-- helm/skybyte-app/     Helm chart
|-- terraform/            Namespace, ResourceQuota, and Secret
|-- policies/             Kyverno admission policies
|-- .github/workflows/    CI workflow
|-- Dockerfile
|-- setup.sh
|-- system-checks.sh
|-- AUDIT.md
|-- DECISIONS.md
`-- CHALLENGE.md
```

## Operational Limitations

- Gunicorn is used as the WSGI runtime, with graceful worker shutdown bounded by the Kubernetes termination grace period.
- There is no ingress, TLS, DNS, or external load balancer configuration yet.
- Kubernetes Secret handling is basic and does not use an external secret manager yet.
- Metrics and an SLO statement are present, but alerting and dashboards are not enforced in this repository.
- Multi-arch image builds, image scanning, and policy checks in CI are planned follow-up work.
