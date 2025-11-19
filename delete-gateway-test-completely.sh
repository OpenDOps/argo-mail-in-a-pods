#!/bin/bash
# Script to completely delete mail-in-a-pods-gateway-test and all bounded resources
# This Gateway uses Cilium GatewayClass but NGINX Gateway Fabric is also managing it

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
GATEWAY_NAME="mail-in-a-pods-gateway-test"

echo "=== Deleting mail-in-a-pods-gateway-test and All Resources ==="
echo ""

echo "Step 1: Delete HTTPRoutes attached to this gateway"
echo "=================================================="
HTTPROUTES=$(kubectl get httproute -n $NAMESPACE -o json 2>/dev/null | jq -r '.items[] | select(.spec.parentRefs[]?.name == "'$GATEWAY_NAME'") | .metadata.name' || echo "")
if [ -n "$HTTPROUTES" ]; then
    echo "$HTTPROUTES" | while read route; do
        if [ -n "$route" ]; then
            echo "  Deleting HTTPRoute: $route"
            kubectl delete httproute $route -n $NAMESPACE --wait=false 2>/dev/null || true
        fi
    done
else
    echo "  No HTTPRoutes found attached to $GATEWAY_NAME"
fi
echo ""

echo "Step 2: Delete Gateway"
echo "====================="
if kubectl get gateway $GATEWAY_NAME -n $NAMESPACE &>/dev/null; then
    echo "Deleting Gateway: $GATEWAY_NAME"
    kubectl delete gateway $GATEWAY_NAME -n $NAMESPACE --wait=false
else
    echo "Gateway $GATEWAY_NAME not found"
fi
echo ""

echo "Step 3: Delete NGINX Gateway Fabric Service"
echo "============================================="
SVC_NAME="${GATEWAY_NAME}-nginx"
if kubectl get svc $SVC_NAME -n $NAMESPACE &>/dev/null; then
    echo "Deleting Service: $SVC_NAME"
    kubectl delete svc $SVC_NAME -n $NAMESPACE --wait=false
else
    echo "Service $SVC_NAME not found"
fi
echo ""

echo "Step 4: Delete NGINX Gateway Fabric Deployment"
echo "==============================================="
DEPLOY_NAME="${GATEWAY_NAME}-nginx"
if kubectl get deployment $DEPLOY_NAME -n $NAMESPACE &>/dev/null; then
    echo "Deleting Deployment: $DEPLOY_NAME"
    kubectl delete deployment $DEPLOY_NAME -n $NAMESPACE --wait=false
else
    echo "Deployment $DEPLOY_NAME not found"
fi
echo ""

echo "Step 5: Delete NGINX Gateway Fabric ConfigMaps"
echo "=============================================="
for cm in $(kubectl get configmap -n $NAMESPACE -o name 2>/dev/null | grep "${GATEWAY_NAME}-nginx" || true); do
    if [ -n "$cm" ]; then
        echo "  Deleting ConfigMap: $cm"
        kubectl delete $cm -n $NAMESPACE --wait=false 2>/dev/null || true
    fi
done
echo ""

echo "Step 6: Delete NGINX Gateway Fabric Secrets"
echo "==========================================="
for secret in $(kubectl get secret -n $NAMESPACE -o name 2>/dev/null | grep "${GATEWAY_NAME}-nginx" || true); do
    if [ -n "$secret" ]; then
        echo "  Deleting Secret: $secret"
        kubectl delete $secret -n $NAMESPACE --wait=false 2>/dev/null || true
    fi
done
echo ""

echo "Step 7: Delete Cilium Gateway Service (if exists)"
echo "================================================="
CILIUM_SVC="cilium-gateway-${GATEWAY_NAME}"
if kubectl get svc $CILIUM_SVC -n $NAMESPACE &>/dev/null; then
    echo "Deleting Cilium Gateway Service: $CILIUM_SVC"
    kubectl delete svc $CILIUM_SVC -n $NAMESPACE --wait=false
else
    echo "Cilium Gateway Service $CILIUM_SVC not found"
fi
echo ""

echo "Step 8: Wait for Gateway to be deleted"
echo "======================================"
echo "Waiting for Gateway to be deleted..."
kubectl wait --for=delete gateway/$GATEWAY_NAME -n $NAMESPACE --timeout=60s 2>/dev/null || echo "Gateway already deleted or timeout"

echo ""
echo "Step 9: Check for remaining resources"
echo "======================================"
echo "Checking for remaining resources..."
REMAINING=$(kubectl get all -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME -o name 2>/dev/null || echo "")
if [ -n "$REMAINING" ]; then
    echo "⚠️  Remaining resources:"
    echo "$REMAINING"
else
    echo "✅ No remaining resources found"
fi

echo ""
echo "=== Deletion Complete ==="
echo ""
echo "Note: If the service keeps being recreated, check:"
echo "  1. Is the Gateway still present? (kubectl get gateway $GATEWAY_NAME -n $NAMESPACE)"
echo "  2. Is NGINX Gateway Fabric watching this Gateway? (check NGINX controller logs)"
echo "  3. Is there an ArgoCD Application managing this Gateway? (check ArgoCD)"
echo ""

