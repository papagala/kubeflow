# KServe v0.16.0 on Kubeflow 1.11.0 — compatibility test

**✅ Pass.** KServe v0.16.0 installs and passes the Kubeflow KServe integration/security
test on community-distribution **v1.11.0** (which ships v0.15.2), on a free `ubuntu-latest` runner.

- Run: https://github.com/papagala/kubeflow/actions/runs/29998295307
- Branch: `test/kserve-0.16.0` (off the `v1.11.0` tag) · sibling: `test/kserve-0.16.0-kf1.10.2` (1.10.2)

## What it runs
Only the `Run KServe Test` step (`tests/kserve_test.sh`) — auth/authorization, path routing,
Knative gateway, namespace isolation — plus the minimal platform it needs, via
`.github/workflows/kserve_only_0_16_test.yaml`.

## Changes vs the v1.11.0 tag
0.16.0 isn't a drop-in bump — the new `llmisvc` stack needs:
- Create the `kserve` namespace (8 `LLMInferenceServiceConfig` CRs are pinned there).
- `sidecar.istio.io/inject: "false"` on `llmisvc-controller-manager` (else the injected sidecar breaks its webhook).
- Wait for the llmisvc webhook before applying the LLM CRs.

CI-only (free runner): single-node KinD (cross-node networking is flaky), restored the gateway
port-forward, and swapped `cluster-jwks-proxy` to `bitnamilegacy/kubectl` (Bitnami retired their Docker Hub images).

## Reproduce
`gh workflow run kserve_only_0_16_test.yaml --repo papagala/kubeflow --ref test/kserve-0.16.0`

## mlops-dev
Runs KServe in an uninjected `kserve` namespace, so the namespace/sidecar fixes don't apply.
The one real item there: the overlay's cert/CA patches must also target the new
`llmisvc-serving-cert` (done in argoflow MR 465).
