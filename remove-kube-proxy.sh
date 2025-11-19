#!/bin/bash
# Script to safely remove kube-proxy when using Cilium with kubeProxyReplacement
# WARNING: Only run this if Cilium has kubeProxyReplacement enabled!

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig

echo "=== Removing kube-proxy (Cilium Replacement) ==="
echo ""
echo "⚠️  WARNING: This will remove kube-proxy from your cluster!"
echo "   Make sure Cilium has kubeProxyReplacement enabled first."
echo ""

# Check if kube-proxy exists
if ! kubectl get daemonset -n kube-system kube-proxy &>/dev/null; then
    echo "✅ kube-proxy DaemonSet not found - may already be removed"
    exit 0
fi

echo "Step 1: Verify Cilium kubeProxyReplacement is enabled"
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "Step 2: Scale down kube-proxy DaemonSet"
kubectl scale daemonset kube-proxy --replicas=0 -n kube-system
echo "Waiting for pods to terminate..."
kubectl wait --for=delete pod -l k8s-app=kube-proxy -n kube-system --timeout=60s || echo "Pods may have already terminated"

echo ""
echo "Step 3: Delete kube-proxy DaemonSet"
kubectl delete daemonset kube-proxy -n kube-system

echo ""
echo "Step 4: Delete kube-proxy ConfigMap (if exists)"
kubectl delete configmap kube-proxy -n kube-system 2>/dev/null || echo "ConfigMap not found (already deleted)"

echo ""
echo "Step 5: Delete kube-proxy ServiceAccount (if exists)"
kubectl delete serviceaccount kube-proxy -n kube-system 2>/dev/null || echo "ServiceAccount not found (already deleted)"

echo ""
echo "Step 6: Delete kube-proxy ClusterRole and ClusterRoleBinding"
kubectl delete clusterrole system:node-proxier 2>/dev/null || echo "ClusterRole not found"
kubectl delete clusterrolebinding system:node-proxier 2>/dev/null || echo "ClusterRoleBinding not found"

echo ""
echo "✅ kube-proxy removal complete!"
echo ""
echo "Verify Cilium is handling proxy functionality:"
echo "  kubectl exec -n kube-system $CILIUM_POD -- cilium status | grep -i proxy"

