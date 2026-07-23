# KServe v0.16.0 compatibility test — Kubeflow **1.11.0**

**Result: ✅ PASS.** KServe **v0.16.0** installs and passes the Kubeflow KServe
integration/security test on the **community-distribution v1.11.0** platform
(which ships KServe v0.15.2), running end-to-end on a free GitHub `ubuntu-latest` runner.

- **Passing run:** https://github.com/papagala/kubeflow/actions/runs/29937558316 (~10 min)
- **Branch:** `test/kserve-0.16.0` (cut from the upstream `v1.11.0` tag)
- **Sibling test (Kubeflow 1.10.2):** branch `test/kserve-0.16.0-kf1.10.2`

> This branch exists **only** to document the KServe-0.16.0-on-Kubeflow-1.11.0
> compatibility test. It is not meant to be merged.

---

## What was tested and why

Context: gRED SM needs the InferenceGraph router `ReadTimeout` fix, which only lands
in **KServe ≥ v0.16.0** (PR kserve/kserve#4218). Question: *does KServe v0.16.0 work on
the Kubeflow 1.11 platform (baseline KServe v0.15.x)?*

The test run here is exactly the **"Run KServe Test"** step (line 200) of the upstream
`full_kubeflow_integration_test.yaml` — i.e. `tests/kserve_test.sh`. It exercises the
real security/authorization surface: unauthenticated requests rejected (403),
valid M2M-token requests accepted, Knative cluster-local-gateway auth, and
cross-namespace ("attacker") isolation. It also runs the sklearn SDK inference pytest.

## Result detail

The whole platform (cert-manager → Istio → OAuth2/Dex → Knative → KServe 0.16.0 →
KF profile) installed cleanly, then all authorization assertions passed (the step uses
`set -e`, so green == every check held):

```
RESPONSE_NO_TOKEN=403                               # no token  -> rejected  ✅
RESPONSE_WITH_TOKEN=404                             # valid M2M -> accepted  ✅
secure-model-predictor: unauth/invalid -> blocked  # Knative auth           ✅
attacker-namespace token -> blocked                # namespace isolation    ✅
```

Nuance: the `test_sklearn.py` pytest sub-check returned 403 and is **tolerated by the
test's own design** (`pytest … || true`, because it runs *before* the allow-policy is
created) — same behavior as the 0.15.x baseline, not a 0.16.0 regression.

**Verdict: KServe v0.16.0 is functionally compatible with the Kubeflow 1.11.0 platform.**
It is *not* a drop-in version bump, though — see the changes below.

---

## What we changed on this branch (vs the `v1.11.0` tag)

### 1. Bump KServe to v0.16.0
`applications/kserve/kserve/*` regenerated via `make upgrade-kserve-manifests KSERVE_VERSION=0.16.0`.
Baseline was v0.15.2.

### 2. Real KServe-0.16.0 fixes (genuine, not CI-only)
KServe 0.16.0 adds a new **LLM inference stack** (`llmisvc` controller + webhooks + 8
default `LLMInferenceServiceConfig` CRs) that breaks a Kubeflow-style install:

| # | Problem | Fix (where) |
|---|---------|-------------|
| a | The 8 `LLMInferenceServiceConfig` CRs are hardcoded to `namespace: kserve`, which the Kubeflow flow never creates → `namespaces "kserve" not found`. | Create the `kserve` namespace before install (workflow step). |
| b | `llmisvc-controller-manager` is missing `sidecar.istio.io/inject: "false"` (which `kserve-controller-manager` has). In the istio-injected `kubeflow` ns, Istio injects a sidecar that black-holes the webhook → `context deadline exceeded`. | Kustomize patch adds the annotation (`applications/kserve/kserve/kustomization.yaml`). |
| c | The install applies the LLM config CRs before the llmisvc webhook is serving. | Wait for `llmisvc-serving-cert` + `llmisvc-controller-manager` before applying (`tests/kserve_install.sh`). |

### 3. CI-environment workarounds (NOT KServe issues)
Needed to run on a free `ubuntu-latest` runner instead of the upstream self-hosted
16-CPU/64-GB Oracle runner:

| Problem | Fix |
|---------|-----|
| Default 3-node KinD has unreliable **cross-node pod networking** on the small runner (pods answer same-node in ~9 ms, time out cross-node) → black-holes `failurePolicy=Fail` webhooks. **This masked issue 2b for two runs.** | Single-node KinD (`tests/install_KinD_create_KinD_cluster_install_kustomize.sh`). Resource-neutral. |
| The trim initially dropped the ingress port-forward the test needs at `localhost:8080`. | Restored the `port_forward_gateway.sh` step. |
| `docker.io/bitnami/kubectl` (used by `cluster-jwks-proxy`) — **Bitnami retired their public Docker Hub images (Aug 2025)**. The original passing run predates this; the image now `ImagePullBackOff`s. | Swap to `docker.io/bitnamilegacy/kubectl` so the branch stays re-runnable. |

### 4. Trimmed test workflow
`.github/workflows/kserve_only_0_16_test.yaml` — runs on free `ubuntu-latest`, drops the
`github.repository == 'kubeflow/manifests'` guard, installs **only** the platform
components `kserve_test.sh` depends on, and runs only the **Run KServe Test** step.
Its `Diagnostics on failure` block includes the A/B webhook reachability probe
(endpoints + in-cluster curl) that pinpointed the cross-node-networking root cause.

---

## How the root cause was found (for the curious)

The llmisvc webhook failed even after removing the sidecar (issue 2b). An A/B probe
(added to diagnostics) showed the kserve webhook answered in **9 ms** while the llmisvc
webhook **timed out at 8 s** — both healthy pods, identical services. The difference was
pod placement: cross-node pod traffic was black-holed on the free runner. Single-node
KinD removed cross-node traffic entirely and the test went green.

---

## How to reproduce

```
gh workflow run kserve_only_0_16_test.yaml --repo papagala/kubeflow --ref test/kserve-0.16.0
gh run watch <run-id> --repo papagala/kubeflow
```

To change the KServe version: `cd applications/kserve && make upgrade-kserve-manifests KSERVE_VERSION=<x.y.z>`, pre-flight `kustomize build kserve`, commit, push.

---

## Relevance to our real cluster (mlops-dev)

mlops-dev runs KServe in its **own `kserve` namespace, which is NOT istio-injected**
(ArgoCD-managed, `namespace: kserve` kustomize remap). So fixes **2a** and **2b** do
**not** apply there — the llmisvc controller/webhook land uninjected and reachable, and
the `kserve` namespace already exists. The CI fixes (single-node, port-forward, bitnami)
are irrelevant to a real cluster.

The one mlops-dev–specific item for the upgrade: their overlay's `ca-injection-patch`
hardcodes `inject-ca-from: kserve/serving-cert` on *all* webhook configs, but 0.16.0's
llmisvc webhook uses a separate `llmisvc-serving-cert`. That patch must be scoped/updated
when bumping, or the ArgoCD sync fails on the llmisvc webhook (wrong CA).
