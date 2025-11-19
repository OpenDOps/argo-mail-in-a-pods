#!/bin/bash
# Script to completely delete mail-in-a-pods-gateway and all bounded resources
# Deletes in correct order to avoid dependency issues

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
GATEWAY_NAME="mail-in-a-pods-gateway"

echo "=== Deleting mail-in-a-pods-gateway and All Resources ==="
echo ""

# Function to delete resource if it exists
delete_resource() {
    local kind=$1
    local name=$2
    local namespace=$3
    
    if kubectl get $kind $name -n $namespace &>/dev/null; then
        echo "Deleting $kind/$name..."
        kubectl delete $kind $name -n $namespace --wait=false
    else
        echo "$kind/$name not found, skipping..."
    fi
}

# Function to delete resources by label
delete_by_label() {
    local kind=$1
    local label=$2
    local namespace=$3
    
    local resources=$(kubectl get $kind -n $namespace -l $label -o name 2>/dev/null || echo "")
    if [ -n "$resources" ]; then
        echo "Deleting $kind with label $label..."
        echo "$resources" | xargs -r kubectl delete -n $namespace --wait=false
    else
        echo "No $kind found with label $label"
    fi
}

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
delete_resource "gateway" "$GATEWAY_NAME" "$NAMESPACE"
echo ""

echo "Step 3: Delete Services created by NGINX Gateway Fabric"
echo "========================================================="
delete_by_label "service" "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" "$NAMESPACE"
# Also check for service with name pattern
SVC_NAME="${GATEWAY_NAME}-nginx"
delete_resource "service" "$SVC_NAME" "$NAMESPACE"
echo ""

echo "Step 4: Delete Deployments created by NGINX Gateway Fabric"
echo "==========================================================="
delete_by_label "deployment" "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" "$NAMESPACE"
# Also check for deployment with name pattern
DEPLOY_NAME="${GATEWAY_NAME}-nginx"
delete_resource "deployment" "$DEPLOY_NAME" "$NAMESPACE"
echo ""

echo "Step 5: Delete ReplicaSets created by NGINX Gateway Fabric"
echo "=========================================================="
delete_by_label "replicaset" "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" "$NAMESPACE"
echo ""

echo "Step 6: Delete ConfigMaps created by NGINX Gateway Fabric"
echo "========================================================="
delete_by_label "configmap" "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" "$NAMESPACE"
# Also check for configmaps with name pattern
for cm in $(kubectl get configmap -n $NAMESPACE -o name 2>/dev/null | grep "$GATEWAY_NAME" || true); do
    if [ -n "$cm" ]; then
        echo "  Deleting ConfigMap: $cm"
        kubectl delete $cm -n $NAMESPACE --wait=false 2>/dev/null || true
    fi
done
echo ""

echo "Step 7: Delete Secrets created by NGINX Gateway Fabric"
echo "======================================================="
delete_by_label "secret" "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" "$NAMESPACE"
# Also check for secrets with name pattern
for secret in $(kubectl get secret -n $NAMESPACE -o name 2>/dev/null | grep "$GATEWAY_NAME" || true); do
    if [ -n "$secret" ]; then
        echo "  Deleting Secret: $secret"
        kubectl delete $secret -n $NAMESPACE --wait=false 2>/dev/null || true
    fi
done
echo ""

echo "Step 8: Wait for resources to be deleted"
echo "========================================="
echo "Waiting for Gateway to be deleted..."
kubectl wait --for=delete gateway/$GATEWAY_NAME -n $NAMESPACE --timeout=60s 2>/dev/null || echo "Gateway already deleted or timeout"

echo "Waiting for Deployments to be deleted..."
for deploy in $(kubectl get deployment -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME -o name 2>/dev/null || echo ""); do
    if [ -n "$deploy" ]; then
        kubectl wait --for=delete $deploy -n $NAMESPACE --timeout=60s 2>/dev/null || true
    fi
done

echo ""
echo "Step 9: Check for remaining resources"
echo "====================================="
echo "Checking for remaining resources with gateway label..."
REMAINING=$(kubectl get all -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME -o name 2>/dev/null || echo "")
if [ -n "$REMAINING" ]; then
    echo "⚠️  Remaining resources:"
    echo "$REMAINING"
    echo ""
    echo "You may need to delete these manually or check for finalizers:"
    echo "$REMAINING" | while read resource; do
        if [ -n "$resource" ]; then
            echo "  kubectl get $resource -n $NAMESPACE -o yaml | grep finalizers"
        fi
    done
else
    echo "✅ No remaining resources found"
fi

echo ""
echo "Step 10: Check for Pods (may take time to terminate)"
echo "====================================================="
PODS=$(kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME -o name 2>/dev/null || echo "")
if [ -n "$PODS" ]; then
    echo "Pods still running (will be terminated by deployment deletion):"
    echo "$PODS"
else
    echo "✅ No pods found"
fi

echo ""
echo "=== Deletion Complete ==="
echo ""
echo "Note: If resources are stuck, check for finalizers:"
echo "  kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o yaml | grep finalizers"
echo ""
echo "To remove finalizers (use with caution):"
echo "  kubectl patch gateway $GATEWAY_NAME -n $NAMESPACE -p '{\"metadata\":{\"finalizers\":[]}}' --type=merge"

