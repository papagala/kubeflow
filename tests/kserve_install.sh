#!/bin/bash
set -euxo pipefail
echo "Installing Kserve ..."
cd applications/kserve
set +e
for ((i=1; i<=3; i++)); do
    if kustomize build kserve | kubectl apply --server-side --force-conflicts -f -; then
        break
    fi
    kubectl wait --for=condition=Ready pods --all --all-namespaces --timeout=60s --field-selector=status.phase!=Succeeded
    kubectl wait --for=condition=Ready certificate/serving-cert -n kubeflow --timeout=60s
    kubectl get secret kserve-webhook-server-cert -n kubeflow -o name
    # KServe 0.16.0: the new llmisvc validating webhook must be ready before the
    # LLMInferenceServiceConfig CRs (shipped in kserve_kubeflow.yaml) can be applied.
    kubectl wait --for=condition=Ready certificate/llmisvc-serving-cert -n kubeflow --timeout=60s
    kubectl wait --for=condition=Available deployment/llmisvc-controller-manager -n kubeflow --timeout=120s
done
set -e

kubectl wait --for condition=established --timeout=30s crd/clusterservingruntimes.serving.kserve.io

# KServe 0.16.0 introduces the llmisvc validating webhook (llminferenceserviceconfig).
# The 8 default LLMInferenceServiceConfig CRs in kserve_kubeflow.yaml are validated by it,
# so the webhook backend must be serving before we (re)apply. Wait for certs + deployments.
kubectl wait --for=condition=Available deployment/kserve-controller-manager -n kubeflow --timeout=300s
kubectl wait --for=condition=Ready certificate/serving-cert -n kubeflow --timeout=120s
kubectl wait --for=condition=Ready certificate/llmisvc-serving-cert -n kubeflow --timeout=120s
kubectl wait --for=condition=Available deployment/llmisvc-controller-manager -n kubeflow --timeout=300s

kustomize build kserve | kubectl apply --server-side --force-conflicts -f -

kustomize build models-web-app/overlays/kubeflow | kubectl apply --server-side --force-conflicts -f -
kubectl wait --for=condition=Ready pods --all --all-namespaces --timeout=600s \
  --field-selector=status.phase!=Succeeded
kubectl wait --for=condition=Available deployment/kserve-controller-manager -n kubeflow --timeout=10s
kubectl wait --for=condition=Available deployment/kserve-models-web-app -n kubeflow --timeout=10s
kubectl get deployment -n kubeflow -l app.kubernetes.io/name=kserve
kubectl get crd | grep -E 'inferenceservice|servingruntimes'

# Return to the original directory
cd ../../
