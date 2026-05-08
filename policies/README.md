# Kubernetes Admission Policies

This directory contains a small Kyverno policy set for runtime standards already used by the `skybyte-app` Deployment.

The policies enforce:

- container images must not use the `latest` tag
- Pods and Deployments must set `runAsNonRoot: true` at pod and container scope
- containers must declare CPU and memory requests and limits

These checks exist to prevent regressions in the hardening already applied to the chart. They are intentionally narrow so the policy layer stays readable and easy to validate.

The policies are written against Pods and rely on Kyverno's controller autogen behavior to apply the same checks to the Helm-rendered Deployment.

Validate rendered manifests with the Kyverno CLI:

```bash
helm template skybyte-app helm/skybyte-app > rendered.yaml
kyverno apply policies/ -r rendered.yaml
```

Apply policies to a cluster with Kyverno installed:

```bash
kubectl apply -f policies/
```

Create a quick rejection example by rendering the chart with a bad image tag:

```bash
helm template skybyte-app helm/skybyte-app --set image.tag=latest > rendered-bad.yaml
kyverno apply policies/ -r rendered-bad.yaml
```
