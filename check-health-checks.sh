#!/bin/bash
# Script to check if health checks are working for the gateway service
# Checks LoadBalancer, Service, Pod, and Endpoint health

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
SERVICE_NAME="mail-in-a-pods-gateway-nginx"

echo "=== Health Check Verification Guide ==="
echo ""

# Get service details
SERVICE_IP=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
EXTERNAL_IP=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
GATEWAY_POD=$(kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

echo "Service: $SERVICE_NAME"
echo "Cluster IP: ${SERVICE_IP:-N/A}"
echo "External IP: ${EXTERNAL_IP:-N/A}"
echo "Gateway Pod: ${GATEWAY_POD:-N/A}"
echo ""

echo "=== 1. Check Service Configuration ==="
echo ""
echo "Service Type and Health Check Port:"
kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.type}{"\n"}{.spec.healthCheckNodePort}{"\n"}{.spec.externalTrafficPolicy}{"\n"}' 2>/dev/null || echo "Service not found"
echo ""

echo "Service Annotations (may contain health check config):"
kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations}' 2>/dev/null | jq -r 'to_entries[] | "\(.key): \(.value)"' 2>/dev/null || kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.metadata.annotations}' 2>/dev/null || echo "No annotations"
echo ""

echo "=== 2. Check Pod Readiness/Liveness Probes ==="
if [ -n "$GATEWAY_POD" ]; then
    echo "Pod: $GATEWAY_POD"
    echo ""
    echo "Readiness Probe:"
    kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.spec.containers[*].readinessProbe}' 2>/dev/null | jq '.' 2>/dev/null || kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.spec.containers[*].readinessProbe}' 2>/dev/null || echo "No readiness probe configured"
    echo ""
    echo "Liveness Probe:"
    kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.spec.containers[*].livenessProbe}' 2>/dev/null | jq '.' 2>/dev/null || kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.spec.containers[*].livenessProbe}' 2>/dev/null || echo "No liveness probe configured"
    echo ""
    echo "Pod Readiness Status:"
    kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")]}' 2>/dev/null | jq '.' 2>/dev/null || kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")]}' 2>/dev/null || echo "Status not available"
    echo ""
else
    echo "Gateway pod not found"
    echo ""
fi

echo "=== 3. Check Service Endpoints ==="
echo ""
echo "Endpoints for $SERVICE_NAME:"
kubectl get endpoints $SERVICE_NAME -n $NAMESPACE -o wide
echo ""
echo "Endpoint Details:"
kubectl get endpoints $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}{"\n"}{.subsets[*].ports[*].port}{"\n"}' 2>/dev/null || echo "No endpoints"
echo ""

echo "=== 4. Test Health Check Endpoint Directly ==="
echo ""
if [ -n "$GATEWAY_POD" ]; then
    echo "Testing health check from inside the pod:"
    echo "Command: kubectl exec -n $NAMESPACE $GATEWAY_POD -- curl -s http://localhost:80/health || curl -s http://localhost:80/"
    echo ""
    echo "Executing..."
    kubectl exec -n $NAMESPACE $GATEWAY_POD -c nginx -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:80/ 2>&1 || echo "Failed to test from pod"
    echo ""
    
    echo "Testing via service ClusterIP:"
    if [ -n "$SERVICE_IP" ]; then
        TEST_POD=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$TEST_POD" ]; then
            kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://${SERVICE_IP}:80/ 2>&1 || echo "Failed"
        else
            echo "No test pod available"
        fi
    fi
    echo ""
else
    echo "Gateway pod not found, skipping direct tests"
    echo ""
fi

echo "=== 5. Check LoadBalancer Health Check Port (NodePort) ==="
echo ""
HEALTH_CHECK_NODEPORT=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.healthCheckNodePort}' 2>/dev/null || echo "")
if [ -n "$HEALTH_CHECK_NODEPORT" ] && [ "$HEALTH_CHECK_NODEPORT" != "null" ]; then
    echo "Health Check NodePort: $HEALTH_CHECK_NODEPORT"
    echo ""
    echo "Testing health check on each node:"
    for node in $(kubectl get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
        echo "Testing node $node:$HEALTH_CHECK_NODEPORT..."
        curl -s -o /dev/null -w "  HTTP Status: %{http_code}\n" --connect-timeout 3 http://${node}:${HEALTH_CHECK_NODEPORT}/ 2>&1 || echo "  Failed to connect"
    done
    echo ""
else
    echo "No healthCheckNodePort configured (service may not be LoadBalancer or externalTrafficPolicy is Cluster)"
    echo ""
fi

echo "=== 6. Check LoadBalancer Provider Health Check (Vultr) ==="
echo ""
if [ -n "$EXTERNAL_IP" ]; then
    echo "External IP: $EXTERNAL_IP"
    echo ""
    echo "Vultr LoadBalancer health checks typically:"
    echo "  - Check the service's NodePort on each node"
    echo "  - Use the port specified in the service"
    echo "  - Expect HTTP 200 response"
    echo ""
    echo "To check Vultr LoadBalancer status, you can:"
    echo "  1. Check Vultr console for LoadBalancer health status"
    echo "  2. Test external IP directly:"
    echo "     curl -v http://${EXTERNAL_IP}/"
    echo ""
    echo "Testing external IP:"
    curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" --connect-timeout 5 http://${EXTERNAL_IP}/ 2>&1 || echo "Failed to connect (may be normal if firewall blocks direct IP)"
    echo ""
else
    echo "No external IP assigned yet"
    echo ""
fi

echo "=== 7. Check Service Status ==="
echo ""
echo "Service Status:"
kubectl get svc $SERVICE_NAME -n $NAMESPACE -o wide
echo ""
echo "Service Events (may show health check issues):"
kubectl get events -n $NAMESPACE --field-selector involvedObject.name=$SERVICE_NAME --sort-by='.lastTimestamp' | tail -10 || echo "No recent events"
echo ""

echo "=== 8. Check Pod Events (for probe failures) ==="
if [ -n "$GATEWAY_POD" ]; then
    echo "Pod Events for $GATEWAY_POD:"
    kubectl get events -n $NAMESPACE --field-selector involvedObject.name=$GATEWAY_POD --sort-by='.lastTimestamp' | tail -10 || echo "No recent events"
    echo ""
    
    echo "Pod Status:"
    kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.status.containerStatuses[*].ready}{"\n"}{.status.containerStatuses[*].restartCount}{"\n"}' 2>/dev/null || echo "Status not available"
    echo ""
fi

echo "=== 9. Monitor Health Checks in Real-Time ==="
echo ""
echo "To monitor health checks continuously:"
echo ""
echo "Terminal 1 - Watch endpoints:"
echo "  watch -n 1 'kubectl get endpoints $SERVICE_NAME -n $NAMESPACE'"
echo ""
echo "Terminal 2 - Watch pod status:"
if [ -n "$GATEWAY_POD" ]; then
    echo "  watch -n 1 'kubectl get pod $GATEWAY_POD -n $NAMESPACE'"
else
    echo "  watch -n 1 'kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway'"
fi
echo ""
echo "Terminal 3 - Watch service:"
echo "  watch -n 1 'kubectl get svc $SERVICE_NAME -n $NAMESPACE'"
echo ""

echo "=== 10. Common Health Check Issues ==="
echo ""
echo "1. Pod not ready:"
echo "   - Check readiness probe configuration"
echo "   - Check pod logs: kubectl logs -n $NAMESPACE $GATEWAY_POD"
echo "   - Check pod events: kubectl describe pod $GATEWAY_POD -n $NAMESPACE"
echo ""
echo "2. Endpoints empty:"
echo "   - Pods must pass readiness probe to be added to endpoints"
echo "   - Check: kubectl get endpoints $SERVICE_NAME -n $NAMESPACE"
echo ""
echo "3. LoadBalancer health check failing:"
echo "   - Check if healthCheckNodePort is accessible from nodes"
echo "   - Check firewall rules for health check port"
echo "   - Verify externalTrafficPolicy (Local requires pod on node)"
echo ""
echo "4. Health check port not accessible:"
echo "   - For externalTrafficPolicy: Local, pod must be on the node"
echo "   - For externalTrafficPolicy: Cluster, any node can respond"
echo "   - Check node port accessibility: curl http://<node-ip>:<healthCheckNodePort>/"
echo ""

echo "=== Quick Health Check Test ==="
echo ""
echo "Run this to quickly test all health check components:"
echo ""
echo "  # Test pod health"
if [ -n "$GATEWAY_POD" ]; then
    echo "  kubectl exec -n $NAMESPACE $GATEWAY_POD -c nginx -- curl -s http://localhost:80/ | head -1"
fi
echo ""
echo "  # Test service endpoint"
if [ -n "$SERVICE_IP" ]; then
    echo "  curl -s http://${SERVICE_IP}:80/ | head -1"
fi
echo ""
echo "  # Test external IP (if available)"
if [ -n "$EXTERNAL_IP" ]; then
    echo "  curl -s http://${EXTERNAL_IP}/ | head -1"
fi
echo ""

