#!/bin/bash
# Script to observe NodePort traffic with Hubble
# Helps debug if NodePort packets reach the pod

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
GATEWAY_NAME="gateway-test-nginx"

echo "=== Hubble NodePort Traffic Observation ==="
echo ""

# Get pod and service information
GATEWAY_POD=$(kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
POD_IP=$(kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
SERVICE_IP=$(kubectl get svc ${GATEWAY_NAME}-nginx -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
NODEPORT=$(kubectl get svc ${GATEWAY_NAME}-nginx -n $NAMESPACE -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}' 2>/dev/null || echo "")
NODE_IP=$(kubectl get pod $GATEWAY_POD -n $NAMESPACE -o jsonpath='{.status.hostIP}' 2>/dev/null || echo "")

echo "Gateway Pod: ${GATEWAY_POD:-N/A}"
echo "Pod IP: ${POD_IP:-N/A}"
echo "Service ClusterIP: ${SERVICE_IP:-N/A}"
echo "NodePort: ${NODEPORT:-N/A}"
echo "Node Internal IP: ${NODE_IP:-N/A}"
echo "Node External IP: 95.179.147.120"
echo ""

# Check if Hubble Relay is running
if ! kubectl get pods -n kube-system -l k8s-app=hubble-relay 2>/dev/null | grep -q Running; then
    echo "❌ Hubble Relay is not running"
    echo "Please enable Hubble first"
    exit 1
fi

echo "✅ Hubble Relay is running"
echo ""

echo "=== Step 1: Port-forward Hubble Relay ==="
echo "Run this in a separate terminal:"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""

echo "=== Step 2: Set HUBBLE_SERVER ==="
echo "  export HUBBLE_SERVER=localhost:4245"
echo ""

echo "=== Observation Methods ==="
echo ""

echo "1. Filter by Pod IP (Most Direct):"
if [ -n "$POD_IP" ]; then
    echo "   hubble observe --ip $POD_IP --follow --last 50"
    echo "   # This shows all traffic to/from the pod"
else
    echo "   hubble observe --ip <pod-ip> --follow --last 50"
fi
echo ""

echo "2. Filter by Pod Name:"
if [ -n "$GATEWAY_POD" ]; then
    echo "   hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --follow --last 50"
else
    echo "   hubble observe --pod <pod-name> --namespace $NAMESPACE --follow --last 50"
fi
echo ""

echo "3. Filter by Service ClusterIP:"
if [ -n "$SERVICE_IP" ]; then
    echo "   hubble observe --ip $SERVICE_IP --follow --last 50"
    echo "   # Shows traffic to the service (includes NodePort)"
else
    echo "   hubble observe --ip <service-ip> --follow --last 50"
fi
echo ""

echo "4. Filter by Port (NodePort):"
if [ -n "$NODEPORT" ]; then
    echo "   hubble observe --port $NODEPORT --follow --last 50"
    echo "   # Shows all traffic on NodePort (may include other services)"
else
    echo "   hubble observe --port <nodeport> --follow --last 50"
fi
echo ""

echo "5. Filter by Node IP (Source):"
echo "   hubble observe --ip 95.179.147.120 --follow --last 50"
echo "   # Shows traffic from/to the node"
echo ""

echo "6. Combined Filters (Pod + Port):"
if [ -n "$GATEWAY_POD" ] && [ -n "$NODEPORT" ]; then
    echo "   hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --port $NODEPORT --follow --last 50"
else
    echo "   hubble observe --pod <pod-name> --namespace $NAMESPACE --port <nodeport> --follow --last 50"
fi
echo ""

echo "=== Testing Workflow ==="
echo ""
echo "Terminal 1: Port-forward Hubble"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""
echo "Terminal 2: Observe traffic"
echo "  export HUBBLE_SERVER=localhost:4245"
if [ -n "$POD_IP" ]; then
    echo "  hubble observe --ip $POD_IP --follow --last 20"
else
    echo "  hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --follow --last 20"
fi
echo ""
echo "Terminal 3: Make NodePort request"
echo "  curl -v http://95.179.147.120:${NODEPORT}/ -H 'Host: mailer2.kuprin.su'"
echo ""
echo "Terminal 4: Make LoadBalancer request (for comparison)"
echo "  curl -v http://95.179.142.249/ -H 'Host: mailer2.kuprin.su'"
echo ""

echo "=== What to Look For ==="
echo ""
echo "1. **NodePort Request**:"
echo "   - Does traffic appear in Hubble?"
echo "   - Does it reach the pod IP ($POD_IP)?"
echo "   - What is the verdict (FORWARDED/DROPPED)?"
echo "   - Is there a response flow?"
echo ""
echo "2. **LoadBalancer Request** (for comparison):"
echo "   - Does traffic appear in Hubble?"
echo "   - Does it reach the pod IP?"
echo "   - What is different from NodePort?"
echo ""
echo "3. **Key Differences**:"
echo "   - Source IP differences"
echo "   - Port differences"
echo "   - Verdict differences (FORWARDED vs DROPPED)"
echo "   - Response flow differences"
echo ""

echo "=== Advanced Filters ==="
echo ""
echo "Filter by protocol and port:"
echo "  hubble observe --protocol tcp --port $NODEPORT --follow --last 50"
echo ""
echo "Filter by verdict (to see dropped packets):"
echo "  hubble observe --verdict DROPPED --ip $POD_IP --follow --last 50"
echo ""
echo "Filter by HTTP (if available):"
echo "  hubble observe --protocol http --ip $POD_IP --follow --last 50"
echo ""

echo "=== JSON Output for Analysis ==="
echo ""
echo "Get detailed flow information:"
if [ -n "$POD_IP" ]; then
    echo "  hubble observe --ip $POD_IP --last 10 --output json | jq '.'"
else
    echo "  hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --last 10 --output json | jq '.'"
fi
echo ""

echo "=== Quick Test Command ==="
echo ""
echo "Run this to test and observe:"
echo "  export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig && \\"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &"
echo "  sleep 2 && \\"
echo "  export HUBBLE_SERVER=localhost:4245 && \\"
if [ -n "$POD_IP" ]; then
    echo "  hubble observe --ip $POD_IP --follow --last 20 &"
else
    echo "  hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --follow --last 20 &"
fi
echo "  sleep 1 && \\"
echo "  curl -v http://95.179.147.120:${NODEPORT}/ -H 'Host: mailer2.kuprin.su'"
echo ""

