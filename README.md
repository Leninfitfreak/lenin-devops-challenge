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
- Kyverno CLI for local policy validation

## Quick Start

Create or select a Kubernetes cluster, then provide the application token for Terraform:

```bash
export TF_VAR_api_token="local-dev-token"
./setup.sh
./system-checks.sh
```

`setup.sh` builds the Docker image, loads it into the `skybyte-devops` Kind cluster when that cluster exists, applies Terraform, and installs or upgrades the Helm release.

By default, the image tag is the current Git short SHA. Set `IMAGE_TAG` to deploy a specific tag:

```bash
IMAGE_TAG=1.0.0 ./setup.sh
```

## Deployment Flow

- Docker builds `skybyte/app:<tag>` from the Flask application.
- Terraform creates the `devops-challenge` namespace, memory quota, and `api-token` Secret.
- Helm deploys the Kubernetes Deployment and Service.
- Kind is used for local Kubernetes runtime validation and local image loading.
- Kubernetes runs the app with non-root settings, probes, resource limits, and Prometheus scrape annotations.

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

Metrics include request count and request duration with `method`, `path`, and `status` labels. The pod template includes Prometheus scrape annotations for `/metrics` on port `80`.

## Admission Policies

Kyverno policies live in `policies/` and enforce the runtime standards already used by the chart:

- images must not use the `latest` tag
- workloads must run as non-root

Validate rendered manifests locally:

```bash
helm template skybyte-app helm/skybyte-app > rendered.yaml
kyverno apply policies/ -r rendered.yaml
```

Apply policies to a cluster with Kyverno installed:

```bash
kubectl apply -f policies/
```

## CI Validation

GitHub Actions runs a single validation job on push and pull request. The workflow currently checks:

- Python dependency installation
- pytest
- Docker image build
- Helm lint
- Helm template rendering
- Terraform formatting
- Terraform validation

Extended CI checks such as Python linting, kubeconform, Trivy scanning, buildx multi-arch builds, and Kyverno policy checks are planned follow-up work.

## Runtime Hardening

The Helm chart configures:

- non-root pod and container execution
- `allowPrivilegeEscalation: false`
- `readOnlyRootFilesystem: true`
- dropped Linux capabilities with only `NET_BIND_SERVICE` added back
- `RuntimeDefault` seccomp profile
- CPU and memory requests and limits
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

- Flask's built-in server is still used for this challenge and local validation; Gunicorn and explicit SIGTERM draining are deferred.
- There is no ingress, TLS, DNS, or external load balancer configuration yet.
- Kubernetes Secret handling is basic and does not use an external secret manager yet.
- Metrics are exposed, but formal SLOs, alerting, and dashboards are not enforced in this repository.
- Advanced CI security scanning and schema validation are planned follow-up work.
