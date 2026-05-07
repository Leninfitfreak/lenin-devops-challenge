# Inherited System Audit

Notes from reviewing the skybyte-app deployment pipeline.

## Security

**Secret hardcoded in three places**

Files: helm/skybyte-app/values.yaml, terraform/variables.tf, helm/skybyte-app/templates/deployment.yaml

Issue: API token hardcoded in chart values, Terraform defaults, and pod env var. Terraform creates a Kubernetes Secret that's never used.

Impact: Anyone with repo/state access can grab production credentials. Secret rotation requires redeployment.

Fix: Remove hardcoded token. Update deployment to use `secretKeyRef` pointing to the Secret already created by Terraform.

---

**Container runs as root**

File: Dockerfile

Issue: No `USER` directive. Runs as UID 0.

Impact: App vulnerability could allow escape to host.

Fix: Add `RUN useradd -m appuser` and `USER appuser` before CMD.

---

**Missing securityContext**

File: helm/skybyte-app/templates/deployment.yaml

Issue: No `runAsNonRoot`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem`, capability drop, or seccompProfile.

Impact: Container can write to filesystem, escalate privileges, and make unrestricted kernel calls if compromised.

Fix: Add container `securityContext`: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, `capabilities: {drop: ["ALL"]}`, `seccompProfile: {type: RuntimeDefault}`.

---

**Image tag `:latest`**

Files: helm/skybyte-app/values.yaml, setup.sh

Issue: Using `:latest`. Redeploy pulls different image. Version unknown.

Impact: Can't debug regressions or rollback reliably. Security patches/breaking changes silently propagate.

Fix: Use semantic version or git SHA. Update values.yaml and setup.sh.

---

**Full base image (python:3.9 instead of slim)**

File: Dockerfile

Issue: Full Debian image when slim/distroless available.

Impact: Larger image, slower deployment.

Fix: Switch to slim or distroless. Verify app runs first.

---

## Reliability

**Health probes misconfigured**

File: helm/skybyte-app/templates/deployment.yaml

Issue: Probes only define path/port. Missing `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`. Also point to `/` instead of `/healthz`.

Impact: Pods fail startup checks. Slow failure detection. Requests routed to unhealthy pods.

Fix: Change to `/healthz`. Add: `initialDelaySeconds: 2`, `periodSeconds: 5`, `timeoutSeconds: 2`, `failureThreshold: 3` (liveness) or `1` (readiness).

---

**No resource requests/limits**

File: helm/skybyte-app/templates/deployment.yaml

Issue: Container has no CPU/memory requests or limits.

Impact: Pod can starve other workloads. Scheduler can't place pods. Pod evicted without warning.

Fix: Add `resources: requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 256Mi}`.

---

**No graceful shutdown**

Files: app/main.py, helm/skybyte-app/templates/deployment.yaml

Issue: Flask's `app.run()` doesn't handle SIGTERM. No `terminationGracePeriodSeconds`.

Impact: In-flight requests drop during pod termination and rolling updates.

Fix: Replace Flask dev server with gunicorn. Add `terminationGracePeriodSeconds: 30`. Add signal handlers to drain requests before exit.

## CI/CD

**No CI pipeline**

File: README.md claims `.github/workflows/ci.yml` but doesn't exist.

Issue: No automated validation on push. README mentions linting, Helm validation, Terraform validation, Docker build—none run.

Impact: Invalid manifests merge to main. Configuration drift.

Fix: Create `.github/workflows/ci.yml` with: Python linting, hadolint, `helm lint`, `terraform validate`, `pytest`, Docker build/push.

---

**setup.sh is unsafe**

File: setup.sh

Issue: `terraform apply -auto-approve` skips review. No error handling. Assumes namespace exists. Hard-coded `:latest` tag.

Impact: Unreviewed changes applied. Silent failures. Unpredictable deployments.

Fix: Add `set -e`. Remove `-auto-approve`. Add `--create-namespace --namespace devops-challenge` to Helm install. Use versioned tag.

---

**Requirements not pinned**

File: app/requirements.txt

Issue: Only `flask==2.3.3` listed. No transitive dependency pins or lock file.

Impact: Different environments get different versions. Hard to reproduce issues.

Fix: Generate `requirements-lock.txt` with `pip freeze`. Update Dockerfile to use it.

## Observability

**No metrics endpoint**

File: app/main.py

Issue: No `/metrics` endpoint for Prometheus.

Impact: No visibility into request behavior.

Fix: Add `/metrics` using `prometheus_client`. Expose `http_requests_total` and `http_request_duration_seconds` histogram.

## Operations

**Helm namespace hardcoded**

Files: helm/skybyte-app/values.yaml, helm/skybyte-app/templates/deployment.yaml

Issue: Chart forces `namespace: devops-challenge` in values instead of using `.Release.Namespace`.

Impact: Chart not reusable across namespaces. Namespace mismatches possible.

Fix: Remove `namespace` from values. Use `.Release.Namespace` in templates.

---

**Tests exist but never run**

File: app/tests/test_main.py

Issue: Tests written but not run in CI, Dockerfile, or setup.

Impact: Tests become stale. Regressions not caught.

Fix: Add pytest step to CI before image build. Document in README.

---

**README out of sync**

File: README.md

Issue: Claims CI that doesn't exist. Says probes use `/healthz` but they use `/`. Doesn't explain secret management.

Impact: New engineers confused about actual state.

Fix: Sync README with implementation.

---

**Missing .dockerignore and incomplete .gitignore**

Issue: No `.dockerignore` file; build includes test artifacts. `.gitignore` may not exclude `.tfstate*`, `.env`, IDE dirs.

Impact: Larger images. Terraform state/local config risk.

Fix: Add `.dockerignore` excluding `__pycache__`, `*.pyc`, `.pytest_cache`. Update `.gitignore` to include `.tfstate*`, `.env`, `__pycache__`, `.pytest_cache`, `.vscode/`, `.idea/`.

---

Priority order: fix secrets and securityContext first. Then health probes and resource limits. Then CI pipeline and observability.

Critical blockers for any production run: secret exposure, non-root user, basic securityContext.

