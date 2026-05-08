# Engineering Decisions

This repository is production-oriented, but it is not a complete production platform. The goal of this pass was to stabilize an inherited Kubernetes deployment with small, defensible changes while keeping the application and deployment flow understandable.

## Architectural Decisions

### Decision: Keep Terraform responsible for namespace-level prerequisites

**Context:** The application needs a namespace, a memory quota, and an API token Secret before the Helm release can run successfully.

**Options considered:** Manage everything in Helm, which would keep deployment in one tool but mix infrastructure prerequisites with application release state. Manage prerequisites in Terraform, which keeps cluster setup separate but requires Terraform state.

**Chosen:** Terraform manages the namespace, ResourceQuota, and Kubernetes Secret.

**Rationale:** These resources are prerequisites for the app rather than part of the app rollout itself. Keeping them in Terraform makes the dependency order explicit and lets Helm focus on the Deployment and Service.

**Cost / risk accepted:** The Kubernetes Secret value is managed through Terraform, which means state handling matters. ResourceQuota is intentionally small and sized for this challenge namespace. A production setup should use encrypted remote state, stronger secret management, and environment-specific quota sizing.

### Decision: Keep Helm responsible for the application release

**Context:** The application workload needs repeatable Deployment and Service rendering with environment-specific values such as image tag, replica count, service port, and resource settings.

**Options considered:** Use plain Kubernetes YAML, which is simple but harder to parameterize. Use Terraform for Kubernetes workloads, which centralizes state but makes app release operations less natural. Use Helm, which adds templating but fits application release management.

**Chosen:** Helm manages the Deployment, Service, release lifecycle, and image tag override.

**Rationale:** Helm is a practical fit for installing, upgrading, rendering, and rolling back a small Kubernetes application. The chart keeps the workload deployable without hardcoding runtime-specific values into templates.

**Cost / risk accepted:** Helm templating adds another layer to debug. The workflow uses `helm lint` and `helm template` to catch basic chart issues before deployment.

### Decision: Use Kind for local runtime validation

**Context:** Static validation is not enough to prove that the image, Terraform resources, Helm release, probes, and Service behave together in Kubernetes.

**Options considered:** Validate only with local Flask and rendered YAML, which is fast but does not exercise Kubernetes. Use Minikube, which is valid but heavier for this local workflow. Use Kind, which runs real Kubernetes components in Docker and works well for local deployment checks.

**Chosen:** Validate the deployment against a local Kind cluster named `skybyte-devops`.

**Rationale:** Kind provides a realistic Kubernetes API and scheduler path while staying lightweight. It was chosen to prioritize local reproducibility and Kubernetes runtime validation over cloud-provider-specific integrations. It also supports loading the locally built image directly into the cluster node, which avoids requiring an external image registry for this challenge.

**Cost / risk accepted:** Kind is not a managed cloud cluster. It does not prove cloud load balancers, managed IAM, ingress controllers, storage classes, or production networking behavior.

### Decision: Replace `latest` with deterministic image tags

**Context:** The original deployment used `latest`, which makes it difficult to identify what source revision is running.

**Options considered:** Keep `latest`, which is convenient but ambiguous. Use a manually supplied semantic version, which is clear but easy to forget in local development. Use the current Git short SHA as the default tag, which is traceable and automatic.

**Chosen:** `setup.sh` defaults `IMAGE_TAG` to `git rev-parse --short HEAD` and passes that tag to Helm.

**Rationale:** A Git-derived tag ties the local Docker image, Kind-loaded image, and Helm deployment to the same source revision. This improves debugging and reproducibility without adding a registry workflow.

**Cost / risk accepted:** Git short SHA tags are not as strong as immutable image digests. A production pipeline should publish images to a registry and deploy by digest or by a controlled release tag.

## Operational Tradeoffs

### Decision: Add Prometheus-compatible metrics without adding a monitoring stack

**Context:** The service needed basic request visibility, but the repository is intentionally small.

**Options considered:** Add a full Prometheus and Grafana stack, which would be useful but too large for this phase. Add OpenTelemetry, which is more flexible but broader than the current need. Add a lightweight `/metrics` endpoint with Prometheus text format.

**Chosen:** Add `/metrics` using `prometheus_client`, with request counter and duration histogram labels for method, path, and status.

**Rationale:** This gives useful operational signals while keeping the application simple. Prometheus scrape annotations make the pod discoverable by a standard scraper without introducing Prometheus Operator or ServiceMonitor resources.

**Cost / risk accepted:** The repository exposes the raw metrics needed for request-rate and latency analysis, but it does not yet define or enforce formal latency or availability objectives. There is no alerting, dashboarding, long-term storage, or SLO burn-rate logic in this repository.

### Decision: Harden the Kubernetes runtime before changing application architecture

**Context:** The inherited Deployment lacked important runtime controls.

**Options considered:** Rewrite the app server first, which would improve serving behavior but touch application runtime assumptions. Harden Kubernetes runtime settings first, which reduces risk with a smaller deployment-focused change.

**Chosen:** Add non-root execution, seccomp, dropped capabilities, read-only root filesystem, resource requests and limits, and health probes.

**Rationale:** These settings reduce blast radius and make scheduler and kubelet behavior more predictable. They also address the highest-risk Kubernetes defects without redesigning the app.

**Cost / risk accepted:** The app now uses Gunicorn instead of Flask's built-in server. The configuration uses one worker to keep Prometheus metrics simple and accurate without adding multiprocess metrics handling.

### Decision: Run the container on an unprivileged port

**Context:** The app originally listened on port 80 inside the container. That required `NET_BIND_SERVICE` for non-root execution and weakened the otherwise strict capability posture.

**Options considered:** Keep port 80 and allow only `NET_BIND_SERVICE`, which preserves the old runtime port but keeps one added capability. Move the container to port 8080 while keeping the Kubernetes Service on port 80, which removes the capability need while preserving Service behavior.

**Chosen:** Run Gunicorn on container port 8080 and keep the Service exposed on port 80.

**Rationale:** The Service remains reachable the same way, but the container no longer binds a privileged port. This lets the chart drop all Linux capabilities without adding one back.

**Cost / risk accepted:** There is a small internal port migration across Docker, Helm, probes, metrics annotations, and runtime checks. The external Service contract is unchanged.

### Decision: Use Kubernetes Secret and `secretKeyRef` for the API token

**Context:** The token should not live in Helm values or application source.

**Options considered:** Keep the token in values, which is simple but unsafe. Create the Secret directly in Helm, which couples secret material to app release values. Create it with Terraform and consume it through `secretKeyRef`.

**Chosen:** Terraform creates `api-token`; the Deployment reads it through `secretKeyRef`.

**Rationale:** This removes the secret from chart values and makes the app consume configuration through Kubernetes-native environment injection.

**Cost / risk accepted:** Kubernetes Secrets are not a complete production secret management solution. External secret managers, encryption controls, and stricter RBAC are deferred.

### Decision: Add a small Kyverno policy layer

**Context:** The Deployment already avoids `latest` image tags and runs as non-root. Those standards should be enforced so future chart changes do not silently weaken the runtime posture.

**Options considered:** Add no policy layer, which keeps the repo smaller but relies on manual review. Add many baseline policies, which is broader but harder to validate in this inherited repository. Add two focused Kyverno policies that match the hardening already implemented.

**Chosen:** Add Kyverno policies to disallow `latest` image tags, require non-root execution, and require CPU and memory requests and limits. Apply them during `setup.sh` before the Helm release.

**Rationale:** Kyverno policies are close to Kubernetes YAML and fit this repository better than introducing a larger policy framework. Applying them during setup makes the local deployment path match the intended admission baseline instead of leaving policy enforcement as a separate manual step. The resource policy matches the chart's request and limit model and the namespace ResourceQuota.

**Cost / risk accepted:** This is not a complete admission baseline. Additional policies for read-only root filesystem, capabilities, and seccomp are deferred.

## Debugging And Validation Approach

### Decision: Validate incrementally before expanding tooling

**Context:** The inherited repository had multiple issues across Docker, Helm, Terraform, and Kubernetes. A large pipeline all at once would make failures harder to isolate.

**Options considered:** Build a complete enterprise-style CI pipeline immediately, which would cover more cases but increase complexity. Add a minimal validation pipeline first and expand it in later phases.

**Chosen:** Add a single GitHub Actions workflow that installs dependencies, lints Python, runs tests, scans the repository with Trivy, builds the image, renders Helm, validates manifests with kubeconform, and validates Terraform.

**Rationale:** This catches the most likely regressions while keeping the workflow readable. The added checks cover Python hygiene, rendered Kubernetes schema validation, and high-severity dependency or secret findings without turning the pipeline into a deployment platform.

**Cost / risk accepted:** The current CI does not yet include buildx multi-arch builds, image scanning, or Kyverno policy validation. Those are planned next-phase improvements.

### Decision: Keep `setup.sh` simple and linear

**Context:** The deployment helper must be easy to inspect and useful for local validation. It also needs to fail before Terraform if the required API token input is missing.

**Options considered:** Add a full argument parser and environment management, which would make the script more flexible but heavier. Keep a small linear script with a few environment overrides and explicit preflight checks.

**Chosen:** Keep `setup.sh` linear: validate `TF_VAR_api_token`, build image, load into Kind when present, apply Terraform, apply Kyverno policies, install or upgrade Helm.

**Rationale:** A small script is easier to debug during an interview or local validation run. `set -euo pipefail` ensures failures stop the deployment instead of continuing silently, and the token preflight turns a later Terraform failure into an immediate operator-readable error.

**Cost / risk accepted:** `terraform apply -auto-approve` remains convenient for local challenge validation but is not the right default for production change control. The policy apply step assumes Kyverno is installed in the target cluster.

### Decision: Use runtime validation in Kind, not only static checks

**Context:** Helm and Terraform can validate syntax while still missing runtime issues such as missing images, bad probes, missing secrets, or Service routing problems.

**Options considered:** Stop at static validation, which is faster but incomplete. Deploy into Kind and verify pod readiness, logs, describe output, deployed image, and metrics endpoint.

**Chosen:** Validate the full local deployment path in Kind.

**Rationale:** Runtime validation proves that Docker, Terraform, Helm, Kubernetes probes, Secret injection, Service routing, and metrics work together.

**Cost / risk accepted:** The runtime validation script covers the core post-deploy checks and pod recovery timing, but it is intentionally not a full test framework.

## Deployment Philosophy

The deployment flow is intentionally small:

```text
Docker image -> Kind image load -> Terraform prerequisites -> Kyverno policies -> Helm release -> Kubernetes runtime validation
```

Terraform and Helm are separated by responsibility. Docker image tagging is deterministic by default. The chart keeps the app deployable with a stable fallback image tag, while `setup.sh` overrides it for local Git-based deployment.

The repository avoids adding large platforms before the basic deployment is stable. The preference is to make one operational improvement at a time, keep the deployment path readable, and verify the result before expanding scope.

## Production Limitations

This repository is not fully production-ready.

Known limitations:

- Gunicorn is configured with a single worker for this service rather than dynamic production tuning.
- SIGTERM handling relies on Gunicorn's graceful worker shutdown and Kubernetes endpoint removal during termination.
- There is no ingress, TLS, DNS, or external load balancer configuration.
- Kubernetes Secret handling is basic and does not use an external secret manager.
- Terraform state protection is not configured in this repository.
- CI does not yet run buildx multi-arch builds, image scanning, or Kyverno policy checks.
- Policy-as-code is intentionally limited to a small Kyverno baseline.
- `system-checks.sh` covers core post-deploy validation and pod recovery timing, but it is not a full synthetic monitoring framework.
- Metrics and an SLO statement are present, but there is no Prometheus deployment, alerting, dashboarding, or SLO enforcement.
- Image tags are deterministic, but images are not published to a registry or pinned by digest.

## Consciously Deferred Work

### WSGI runtime tuning

Deferred beyond the first Gunicorn pass. The current configuration replaces Flask's built-in server and validates rollout behavior, but future work should tune worker count, timeouts, and pod deletion recovery checks against real traffic patterns.

### Ingress and TLS

Deferred because the current service is validated through ClusterIP and port-forward. Ingress should be added only when there is a target ingress controller and hostname model.

### External secret management

Deferred because the first goal was to remove hardcoded secrets and use Kubernetes-native injection. A production version should integrate with Vault, cloud secret managers, External Secrets Operator, SOPS, or a similar controlled workflow.

### Advanced observability

Deferred because the immediate need was application-level request metrics. A formal latency SLO, Prometheus deployment, alert rules, dashboards, log aggregation, and tracing should be added after the basic metrics surface is stable.

### Expanded policy-as-code

Deferred beyond the first Kyverno pass. The current policies enforce non-root execution and block `latest` tags. Future policies should cover resource requests and limits, read-only root filesystem, dropped capabilities, and seccomp.

### Extended CI validation

Deferred beyond the current incremental CI pass. The workflow now includes Python linting, kubeconform, and Trivy filesystem scanning. The next version should add buildx multi-arch builds, image scanning, and Kyverno policy checks against rendered manifests.

### Image registry and digest pinning

Deferred because local Kind validation can use `kind load docker-image`. A production pipeline should push images to a registry and deploy immutable digests.

## Future Improvements

- Expand Kyverno policies and add policy checks to CI.
- Add image scanning to CI.
- Tune Gunicorn worker settings against realistic traffic.
- Add Prometheus query examples for the documented SLO.
- Document Terraform state handling for secret values.
- Publish images to a registry and deploy by digest.
- Add ingress and TLS when a real environment target exists.
