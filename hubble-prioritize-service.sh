#!/bin/bash
# Script to help prioritize Hubble events for specific services
# Note: Hubble doesn't have direct priority, but we can reduce event loss and filter

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
SERVICE_NAME="mail-in-a-pods-gateway-nginx"

echo "=== Prioritizing Hubble Events for Service: $SERVICE_NAME ==="
echo ""

echo "=== Option 1: Increase Hubble Buffer Sizes (Helps All Services) ==="
echo ""
echo "This reduces event loss by increasing buffer capacity:"
echo ""
echo "1. Get current Cilium Helm values:"
echo "   helm get values cilium -n kube-system"
echo ""
echo "2. Upgrade Cilium with increased Hubble buffers:"
echo "   helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \\"
echo "     --set hubble.observer.queueSize=10000 \\"
echo "     --set hubble.observer.ringBufferSize=16384"
echo ""
echo "Default values:"
echo "  - queueSize: 1000 (increase to 10000 or more)"
echo "  - ringBufferSize: 4096 (increase to 16384 or more)"
echo ""

echo "=== Option 2: Filter Hubble Observations to Specific Service ==="
echo ""
echo "Instead of observing all traffic, filter to your service:"
echo ""
SERVICE_IP=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "N/A")
POD_NAME=$(kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "N/A")

echo "A. Filter by Service IP:"
if [ "$SERVICE_IP" != "N/A" ]; then
    echo "   hubble observe --ip $SERVICE_IP --last 100"
else
    echo "   hubble observe --ip <service-cluster-ip> --last 100"
fi
echo ""

echo "B. Filter by Service Name:"
echo "   hubble observe --service $SERVICE_NAME --namespace $NAMESPACE --last 100"
echo ""

echo "C. Filter by Pod:"
if [ "$POD_NAME" != "N/A" ]; then
    echo "   hubble observe --pod $POD_NAME --namespace $NAMESPACE --last 100"
else
    echo "   hubble observe --pod <pod-name> --namespace $NAMESPACE --last 100"
fi
echo ""

echo "=== Option 3: Use Hubble Metrics (More Efficient) ==="
echo ""
echo "Instead of observing all flows, use metrics for monitoring:"
echo ""
echo "1. Port-forward Hubble metrics:"
echo "   kubectl port-forward -n kube-system svc/hubble-metrics 9965:9965"
echo ""
echo "2. Query Prometheus metrics:"
echo "   curl http://localhost:9965/metrics | grep hubble"
echo ""
echo "3. Filter metrics by service:"
echo "   curl 'http://localhost:9965/metrics' | grep -E 'hubble.*$SERVICE_NAME'"
echo ""

echo "=== Option 4: Increase Cilium Agent Resources ==="
echo ""
echo "If Hubble is CPU-bound, increase agent resources:"
echo ""
echo "   helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \\"
echo "     --set resources.requests.cpu=500m \\"
echo "     --set resources.requests.memory=512Mi \\"
echo "     --set resources.limits.cpu=2000m \\"
echo "     --set resources.limits.memory=2Gi"
echo ""

echo "=== Option 5: Reduce Hubble Sampling (Trade-off) ==="
echo ""
echo "Reduce event volume by sampling (loses some events but reduces loss):"
echo ""
echo "   helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \\"
echo "     --set hubble.observer.sampleRate=0.5"
echo ""
echo "sampleRate: 1.0 = all events, 0.5 = 50% of events, 0.1 = 10% of events"
echo ""

echo "=== Option 6: Use Hubble UI with Filters ==="
echo ""
echo "Hubble UI allows filtering in real-time:"
echo ""
echo "1. Port-forward Hubble UI:"
echo "   kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
echo ""
echo "2. Access: http://localhost:12000"
echo ""
echo "3. Use filters in UI:"
echo "   - Namespace: $NAMESPACE"
echo "   - Service: $SERVICE_NAME"
echo "   - Pod: $POD_NAME"
echo ""

echo "=== Recommended Approach ==="
echo ""
echo "1. Increase Hubble buffer sizes (Option 1) - helps all services"
echo "2. Use filtered observations (Option 2) - focus on your service"
echo "3. Monitor with metrics (Option 3) - more efficient for monitoring"
echo ""

echo "=== Quick Command to Monitor Your Service ==="
echo ""
echo "Terminal 1 (Port-forward):"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""
echo "Terminal 2 (Observe with filters):"
echo "  export HUBBLE_SERVER=localhost:4245"
if [ "$POD_NAME" != "N/A" ]; then
    echo "  hubble observe --pod $POD_NAME --namespace $NAMESPACE --follow --last 50"
elif [ "$SERVICE_IP" != "N/A" ]; then
    echo "  hubble observe --ip $SERVICE_IP --follow --last 50"
else
    echo "  hubble observe --service $SERVICE_NAME --namespace $NAMESPACE --follow --last 50"
fi
echo ""

echo "=== Check Current Hubble Configuration ==="
echo ""
echo "Current Cilium ConfigMap Hubble settings:"
kubectl get configmap cilium-config -n kube-system -o yaml 2>/dev/null | grep -E "hubble|observer" | head -15 || echo "No Hubble config found"
echo ""

