#!/bin/bash
# Script to fix and debug Envoy config_dump issues
# Provides alternative methods to get Envoy configuration

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
GATEWAY_NAME="mail-in-a-pods-gateway-test"

echo "=== Envoy config_dump Debugging ==="
echo ""

# Get Envoy pod
ENVOY_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium-envoy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$ENVOY_POD" ]; then
    echo "❌ Envoy pod not found"
    exit 1
fi

echo "Envoy Pod: $ENVOY_POD"
echo ""

echo "=== Method 1: Direct Access (Inside Pod) ==="
echo ""
echo "1. Check if admin interface is accessible:"
echo "   kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/ready"
echo ""
echo "2. Get config_dump directly:"
echo "   kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/config_dump > config_dump.json"
echo ""
echo "3. Check config_dump size:"
echo "   kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/config_dump | wc -l"
echo ""

echo "=== Method 2: Alternative Endpoints ==="
echo ""
echo "If config_dump is empty, try these endpoints:"
echo ""
echo "1. Listeners (shows active listeners):"
echo "   kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/listeners"
echo ""
echo "2. Clusters (shows backend services):"
echo "   kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/clusters"
echo ""
echo "3. Routes (shows HTTP routes):"
echo "   kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/routes"
echo ""
echo "4. Server info:"
echo "   kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/server_info"
echo ""

echo "=== Method 3: Port-Forward with Different Paths ==="
echo ""
echo "1. Port-forward:"
echo "   kubectl port-forward -n kube-system $ENVOY_POD 15000:15000 &"
echo ""
echo "2. Try different config_dump paths:"
echo "   curl http://localhost:15000/config_dump"
echo "   curl http://localhost:15000/config_dump?include_eds"
echo "   curl http://localhost:15000/config_dump?resource=dynamic_listeners"
echo "   curl http://localhost:15000/config_dump?resource=dynamic_route_configs"
echo ""

echo "=== Method 4: Check Envoy Logs ==="
echo ""
echo "Envoy logs may show configuration issues:"
echo "   kubectl logs -n kube-system $ENVOY_POD --tail=100 | grep -i 'config\|listener\|route'"
echo ""

echo "=== Method 5: Get Configuration from Cilium ==="
echo ""
echo "Cilium may have the configuration cached:"
echo "   kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o yaml"
echo "   kubectl get httproute -n $NAMESPACE -o yaml"
echo ""

echo "=== Method 6: Use Cilium CLI ==="
echo ""
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CILIUM_POD" ]; then
    echo "Check Cilium Gateway status:"
    echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium gateway status"
    echo ""
    echo "Check Cilium Gateway routes:"
    echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium gateway list"
fi
echo ""

echo "=== Quick Test Commands ==="
echo ""
echo "# Test 1: Check if admin is accessible"
echo "kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/ready"
echo ""
echo "# Test 2: Get listeners (usually works even if config_dump doesn't)"
echo "kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/listeners | jq '.listener_statuses[] | select(.name | contains(\"$GATEWAY_NAME\"))'"
echo ""
echo "# Test 3: Get clusters (shows backend services)"
echo "kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/clusters | grep -i mailer"
echo ""
echo "# Test 4: Get routes"
echo "kubectl exec -n kube-system $ENVOY_POD -- curl -s http://localhost:15000/routes"
echo ""

echo "=== Troubleshooting Empty config_dump ==="
echo ""
echo "Common causes:"
echo "1. Envoy admin interface disabled or restricted"
echo "2. Config not loaded yet (check Envoy logs)"
echo "3. Wrong endpoint path"
echo "4. Authentication required"
echo ""
echo "Solutions:"
echo "1. Use listeners/clusters endpoints instead"
echo "2. Check Envoy logs for errors"
echo "3. Check Cilium Gateway status"
echo "4. Use Kubernetes resources (Gateway/HTTPRoute) as source of truth"
echo ""

