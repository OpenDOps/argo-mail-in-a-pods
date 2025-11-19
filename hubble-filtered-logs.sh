#!/bin/bash
# Hubble Filtered Logs Script
# Provides various filtering options for Hubble observability

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
GATEWAY_SVC="mail-in-a-pods-gateway-nginx"

echo "=== Hubble Filtered Logs Guide ==="
echo ""
echo "Note: To avoid 'http2: frame too large' errors, use --last flag to limit results"
echo ""

# Get current pod and service info
echo "=== Current Resources ==="
GATEWAY_POD=$(kubectl get pods -n $NAMESPACE -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
GATEWAY_IP=$(kubectl get svc $GATEWAY_SVC -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
MAILINABOX_POD=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=mailinabox -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

echo "Gateway Pod: ${GATEWAY_POD:-N/A}"
echo "Gateway Service IP: ${GATEWAY_IP:-N/A}"
echo "Mailinabox Pod: ${MAILINABOX_POD:-N/A}"
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
echo "Run this in a separate terminal or background:"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &"
echo ""
echo "Or run it in foreground (Ctrl+C to stop):"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""

echo "=== Step 2: Set HUBBLE_SERVER ==="
echo "  export HUBBLE_SERVER=localhost:4245"
echo ""

echo "=== Filtering Options ==="
echo ""

echo "1. Filter by Pod (Gateway):"
if [ -n "$GATEWAY_POD" ]; then
    echo "   hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --last 100"
    echo "   hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --follow"
else
    echo "   hubble observe --pod <pod-name> --namespace $NAMESPACE --last 100"
fi
echo ""

echo "2. Filter by Pod (Mailinabox):"
if [ -n "$MAILINABOX_POD" ]; then
    echo "   hubble observe --pod $MAILINABOX_POD --namespace $NAMESPACE --last 100"
    echo "   hubble observe --pod $MAILINABOX_POD --namespace $NAMESPACE --follow"
else
    echo "   hubble observe --pod <pod-name> --namespace $NAMESPACE --last 100"
fi
echo ""

echo "3. Filter by Service:"
if [ -n "$GATEWAY_IP" ]; then
    echo "   hubble observe --service $GATEWAY_SVC --namespace $NAMESPACE --last 100"
    echo "   hubble observe --service $GATEWAY_SVC --namespace $NAMESPACE --follow"
else
    echo "   hubble observe --service <service-name> --namespace $NAMESPACE --last 100"
fi
echo ""

echo "4. Filter by IP Address:"
if [ -n "$GATEWAY_IP" ]; then
    echo "   hubble observe --ip $GATEWAY_IP --last 100"
    echo "   hubble observe --ip $GATEWAY_IP --follow"
else
    echo "   hubble observe --ip <ip-address> --last 100"
fi
echo ""

echo "5. Filter by Namespace:"
echo "   hubble observe --namespace $NAMESPACE --last 100"
echo "   hubble observe --namespace $NAMESPACE --follow"
echo ""

echo "6. Filter by Protocol:"
echo "   hubble observe --protocol tcp --namespace $NAMESPACE --last 100"
echo "   hubble observe --protocol udp --namespace $NAMESPACE --last 100"
echo "   hubble observe --protocol http --namespace $NAMESPACE --last 100"
echo ""

echo "7. Filter by Port:"
echo "   hubble observe --port 80 --namespace $NAMESPACE --last 100"
echo "   hubble observe --port 443 --namespace $NAMESPACE --last 100"
echo "   hubble observe --port 10222 --namespace $NAMESPACE --last 100"
echo ""

echo "8. Filter by HTTP Status Code:"
echo "   hubble observe --http-status 200 --namespace $NAMESPACE --last 100"
echo "   hubble observe --http-status 404 --namespace $NAMESPACE --last 100"
echo "   hubble observe --http-status 500 --namespace $NAMESPACE --last 100"
echo ""

echo "9. Filter by HTTP Method:"
echo "   hubble observe --http-method GET --namespace $NAMESPACE --last 100"
echo "   hubble observe --http-method POST --namespace $NAMESPACE --last 100"
echo ""

echo "10. Filter by HTTP Path:"
echo "   hubble observe --http-path / --namespace $NAMESPACE --last 100"
echo "   hubble observe --http-path /admin --namespace $NAMESPACE --last 100"
echo ""

echo "11. Filter by Label:"
echo "   hubble observe --label k8s:app=mailinabox --namespace $NAMESPACE --last 100"
echo "   hubble observe --label gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway --namespace $NAMESPACE --last 100"
echo ""

echo "12. Combine Multiple Filters:"
if [ -n "$GATEWAY_POD" ]; then
    echo "   hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --protocol tcp --port 80 --last 100"
    echo "   hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --http-status 200 --last 100"
    echo "   hubble observe --service $GATEWAY_SVC --namespace $NAMESPACE --protocol http --last 100"
fi
echo ""

echo "13. Filter by Flow Type:"
echo "   hubble observe --type trace --namespace $NAMESPACE --last 100"
echo "   hubble observe --type drop --namespace $NAMESPACE --last 100"
echo "   hubble observe --type policy --namespace $NAMESPACE --last 100"
echo ""

echo "14. Filter by Verdict:"
echo "   hubble observe --verdict FORWARDED --namespace $NAMESPACE --last 100"
echo "   hubble observe --verdict DROPPED --namespace $NAMESPACE --last 100"
echo ""

echo "15. Filter by Time Range:"
echo "   hubble observe --since 5m --namespace $NAMESPACE"
echo "   hubble observe --since 1h --namespace $NAMESPACE"
echo "   hubble observe --since 24h --namespace $NAMESPACE"
echo ""

echo "16. Output Formats:"
echo "   hubble observe --namespace $NAMESPACE --last 100 --output json"
echo "   hubble observe --namespace $NAMESPACE --last 100 --output compact"
echo "   hubble observe --namespace $NAMESPACE --last 100 --output table"
echo "   hubble observe --namespace $NAMESPACE --last 100 --output dict"
echo ""

echo "=== Example: Monitor Gateway Traffic ==="
echo ""
echo "Terminal 1 (Port-forward):"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""
echo "Terminal 2 (Observe):"
echo "  export HUBBLE_SERVER=localhost:4245"
if [ -n "$GATEWAY_POD" ]; then
    echo "  hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --follow --last 50"
else
    echo "  hubble observe --service $GATEWAY_SVC --namespace $NAMESPACE --follow --last 50"
fi
echo ""
echo "Terminal 3 (Generate Traffic):"
echo "  curl -v http://95.179.135.8/ -H 'Host: mailer4.kuprin.su'"
echo ""

echo "=== Troubleshooting HTTP/2 Frame Too Large Error ==="
echo ""
echo "If you see 'http2: frame too large' error, try:"
echo "  1. Use --last flag to limit results:"
echo "     hubble observe --namespace $NAMESPACE --last 50"
echo ""
echo "  2. Use more specific filters to reduce data:"
echo "     hubble observe --pod <pod-name> --namespace $NAMESPACE --last 50"
echo ""
echo "  3. Use --since instead of --follow:"
echo "     hubble observe --namespace $NAMESPACE --since 5m"
echo ""
echo "  4. Use JSON output and pipe to jq for filtering:"
echo "     hubble observe --namespace $NAMESPACE --last 100 --output json | jq 'select(.destination.namespace==\"mailer\")'"
echo ""

echo "=== Quick Test Command ==="
echo ""
echo "Run this to test Hubble connection and get recent flows:"
echo "  export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig && \\"
echo "  kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &"
echo "  sleep 2 && \\"
echo "  export HUBBLE_SERVER=localhost:4245 && \\"
if [ -n "$GATEWAY_POD" ]; then
    echo "  hubble observe --pod $GATEWAY_POD --namespace $NAMESPACE --last 20"
else
    echo "  hubble observe --namespace $NAMESPACE --last 20"
fi
echo ""

