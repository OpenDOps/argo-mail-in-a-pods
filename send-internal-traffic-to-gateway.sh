#!/bin/bash
# Script to send internal traffic to the gateway service
# This tests connectivity from within the cluster

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
SERVICE_NAME="mail-in-a-pods-gateway-nginx"
HOSTNAME="mailer4.kuprin.su"

echo "=== Sending Internal Traffic to Gateway ==="
echo ""

# Get service details
SERVICE_IP=$(kubectl get svc $SERVICE_NAME -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
SERVICE_FQDN="${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local"

echo "Gateway Service: $SERVICE_NAME"
echo "Cluster IP: ${SERVICE_IP:-N/A}"
echo "FQDN: $SERVICE_FQDN"
echo "Hostname: $HOSTNAME"
echo ""

# Find a pod to use for testing
echo "=== Finding a pod to send traffic from ==="
TEST_POD=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$TEST_POD" ]; then
    echo "❌ No pods found in namespace $NAMESPACE"
    echo "Creating a temporary curl pod..."
    kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never -n $NAMESPACE -- sh -c "
        echo '=== Testing Gateway via Cluster IP ==='
        curl -v http://${SERVICE_IP}:80/ -H 'Host: $HOSTNAME'
        echo ''
        echo '=== Testing Gateway via FQDN ==='
        curl -v http://${SERVICE_FQDN}:80/ -H 'Host: $HOSTNAME'
    "
else
    echo "Using pod: $TEST_POD"
    echo ""
    
    echo "=== Method 1: Test via Cluster IP ==="
    if [ -n "$SERVICE_IP" ]; then
        echo "Command:"
        echo "  kubectl exec -n $NAMESPACE $TEST_POD -- curl -v http://${SERVICE_IP}:80/ -H 'Host: $HOSTNAME'"
        echo ""
        echo "Executing..."
        kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -w "\nHTTP Status: %{http_code}\n" http://${SERVICE_IP}:80/ -H "Host: $HOSTNAME" 2>&1 || echo "Failed"
        echo ""
    else
        echo "Service IP not found"
        echo ""
    fi
    
    echo "=== Method 2: Test via Service FQDN ==="
    echo "Command:"
    echo "  kubectl exec -n $NAMESPACE $TEST_POD -- curl -v http://${SERVICE_FQDN}:80/ -H 'Host: $HOSTNAME'"
    echo ""
    echo "Executing..."
    kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -w "\nHTTP Status: %{http_code}\n" http://${SERVICE_FQDN}:80/ -H "Host: $HOSTNAME" 2>&1 || echo "Failed"
    echo ""
    
    echo "=== Method 3: Test via Service Name (short) ==="
    echo "Command:"
    echo "  kubectl exec -n $NAMESPACE $TEST_POD -- curl -v http://${SERVICE_NAME}:80/ -H 'Host: $HOSTNAME'"
    echo ""
    echo "Executing..."
    kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -w "\nHTTP Status: %{http_code}\n" http://${SERVICE_NAME}:80/ -H "Host: $HOSTNAME" 2>&1 || echo "Failed"
    echo ""
    
    echo "=== Method 4: Test HTTPS (if configured) ==="
    echo "Command:"
    echo "  kubectl exec -n $NAMESPACE $TEST_POD -- curl -v -k https://${SERVICE_IP}:443/ -H 'Host: $HOSTNAME'"
    echo ""
    echo "Executing..."
    kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -k -w "\nHTTP Status: %{http_code}\n" https://${SERVICE_IP}:443/ -H "Host: $HOSTNAME" 2>&1 || echo "Failed (HTTPS may not be configured)"
    echo ""
fi

echo "=== Gateway Pod Details ==="
GATEWAY_POD=$(kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$GATEWAY_POD" ]; then
    echo "Gateway Pod: $GATEWAY_POD"
    echo "Pod IP: $(kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.status.podIP}')"
    echo ""
    
    echo "=== Test Directly to Gateway Pod ==="
    POD_IP=$(kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.status.podIP}')
    echo "Command:"
    echo "  kubectl exec -n $NAMESPACE $TEST_POD -- curl -v http://${POD_IP}:80/ -H 'Host: $HOSTNAME'"
    echo ""
    echo "Executing..."
    kubectl exec -n $NAMESPACE $TEST_POD -- curl -s -w "\nHTTP Status: %{http_code}\n" http://${POD_IP}:80/ -H "Host: $HOSTNAME" 2>&1 || echo "Failed"
    echo ""
else
    echo "Gateway pod not found"
    echo ""
fi

echo "=== Observe with Hubble ==="
echo ""
echo "To observe this traffic with Hubble:"
echo ""
echo "Terminal 1 (Port-forward Hubble):"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""
echo "Terminal 2 (Observe):"
echo "  export HUBBLE_SERVER=localhost:4245"
if [ -n "$GATEWAY_POD" ]; then
    echo "  hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --follow --last 50"
elif [ -n "$SERVICE_IP" ]; then
    echo "  hubble observe --ip $SERVICE_IP --follow --last 50"
else
    echo "  hubble observe --service $SERVICE_NAME --namespace $NAMESPACE --follow --last 50"
fi
echo ""
echo "Terminal 3 (Send traffic - run this script again):"
echo "  ./send-internal-traffic-to-gateway.sh"
echo ""

echo "=== Quick Test Commands ==="
echo ""
echo "Single command to test and observe:"
echo "  kubectl exec -n $NAMESPACE $TEST_POD -- curl -v http://${SERVICE_NAME}:80/ -H 'Host: $HOSTNAME'"
echo ""

