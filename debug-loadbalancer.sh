#!/bin/bash
# LoadBalancer Debugging Script
# This script helps debug if traffic is reaching the gateway pods

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
SERVICE="mail-in-a-pods-gateway-nginx"
LB_IP="95.179.147.73"
HOSTNAME="mailer4.kuprin.su"

echo "=== LoadBalancer Debugging ==="
echo ""

# 1. Check Service Status
echo "1. Service Status:"
kubectl get service $SERVICE -n $NAMESPACE -o wide
echo ""

# 2. Check Service Endpoints
echo "2. Service Endpoints:"
kubectl get endpoints $SERVICE -n $NAMESPACE
echo ""

# 3. Check Pod Status
echo "3. Gateway Pods:"
kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o wide
echo ""

# 4. Get Pod Name
POD_NAME=$(kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o jsonpath='{.items[0].metadata.name}')
echo "4. Using Pod: $POD_NAME"
echo ""

# 5. Test from inside the pod
echo "5. Testing from inside pod (localhost):"
kubectl exec -n $NAMESPACE $POD_NAME -c nginx -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:80/ -H "Host: $HOSTNAME" || echo "Failed"
echo ""

# 6. Test from inside the pod via service
echo "6. Testing from inside pod (via service):"
kubectl exec -n $NAMESPACE $POD_NAME -c nginx -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://${SERVICE}.${NAMESPACE}.svc.cluster.local:80/ -H "Host: $HOSTNAME" || echo "Failed"
echo ""

# 7. Check active connections
echo "7. Active connections on pod (port 80):"
kubectl exec -n $NAMESPACE $POD_NAME -c nginx -- netstat -an 2>/dev/null | grep ":80 " | grep ESTABLISHED | wc -l | xargs echo "Established connections:"
echo ""

# 8. Check listening ports
echo "8. Listening ports:"
kubectl exec -n $NAMESPACE $POD_NAME -c nginx -- netstat -tlnp 2>/dev/null | grep -E ":80|:443" || kubectl exec -n $NAMESPACE $POD_NAME -c nginx -- ss -tlnp | grep -E ":80|:443"
echo ""

# 9. Check LoadBalancer IP connectivity from pod
echo "9. Testing LoadBalancer IP from pod:"
kubectl exec -n $NAMESPACE $POD_NAME -c nginx -- timeout 5 curl -v http://${LB_IP}/ -H "Host: $HOSTNAME" 2>&1 | head -20 || echo "Connection failed or timed out"
echo ""

# 10. Check service externalTrafficPolicy
echo "10. Service Configuration:"
kubectl get service $SERVICE -n $NAMESPACE -o jsonpath='ExternalTrafficPolicy: {.spec.externalTrafficPolicy}{"\n"}HealthCheckNodePort: {.spec.healthCheckNodePort}{"\n"}LoadBalancerIP: {.status.loadBalancer.ingress[0].ip}{"\n"}'
echo ""

# 11. Check recent service events
echo "11. Recent Service Events:"
kubectl describe service $SERVICE -n $NAMESPACE | tail -15
echo ""

# 12. Monitor logs in real-time (run this separately)
echo "12. To monitor logs in real-time, run:"
echo "   kubectl logs -f -n $NAMESPACE $POD_NAME -c nginx"
echo ""

# 13. Test external connectivity
echo "13. Testing external connectivity (from your machine):"
echo "   Run: curl -v --connect-timeout 5 http://${LB_IP}/ -H 'Host: $HOSTNAME'"
echo ""

echo "=== Debugging Complete ==="
echo ""
echo "Key things to check:"
echo "- If pod responds locally but not externally: LoadBalancer health check issue"
echo "- If no connections in netstat: Traffic not reaching pod"
echo "- Check externalTrafficPolicy: 'Local' requires health check on node"
echo "- Check Vultr LoadBalancer health check configuration"

