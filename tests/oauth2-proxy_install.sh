#!/bin/bash
set -e

echo "Installing oauth2-proxy..."
cd common/
kustomize build oauth2-proxy/overlays/m2m-dex-and-kind/ | kubectl apply -f -

echo "Waiting for all oauth2-proxy pods to become ready..."
kubectl wait --for=condition=Ready pod -l 'app.kubernetes.io/name=oauth2-proxy' --timeout=180s -n oauth2-proxy

echo "Waiting for all cluster-jwks-proxy pods to become ready..."
kubectl wait --for=condition=Ready pod -l 'app.kubernetes.io/name=cluster-jwks-proxy' --timeout=300s -n istio-system || {
  echo "=== cluster-jwks-proxy did not become Ready; dumping diagnostics ==="
  kubectl get pods -n istio-system -l app.kubernetes.io/name=cluster-jwks-proxy -o wide
  kubectl describe pods -n istio-system -l app.kubernetes.io/name=cluster-jwks-proxy
  kubectl logs -n istio-system -l app.kubernetes.io/name=cluster-jwks-proxy --all-containers=true --tail=200 || true
  echo "=== node capacity / allocation ==="
  kubectl top nodes || true
  kubectl describe nodes | grep -A15 "Allocated resources" || true
  exit 1
}
kubectl wait --for=condition=Available deployment -n oauth2-proxy oauth2-proxy --timeout=180s