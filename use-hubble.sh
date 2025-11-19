#!/bin/bash
# Hubble Observability Guide for Cilium Gateway
# Hubble provides network flow visibility for Cilium

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig

echo "=== Hubble Observability for Cilium Gateway ==="
echo ""

# Check if Hubble is available
if kubectl get pods -n kube-system -l k8s-app=hubble-relay 2>/dev/null | grep -q Running; then
    echo "✅ Hubble Relay is running"
    HUBBLE_RELAY_POD=$(kubectl get pods -n kube-system -l k8s-app=hubble-relay -o jsonpath='{.items[0].metadata.name}')
    echo "   Pod: $HUBBLE_RELAY_POD"
else
    echo "❌ Hubble Relay is not running"
    echo ""
    echo "To enable Hubble, run:"
    echo "  helm upgrade cilium cilium/cilium --namespace kube-system --reuse-values \\"
    echo "    --set hubble.enabled=true \\"
    echo "    --set hubble.relay.enabled=true \\"
    echo "    --set hubble.ui.enabled=true"
    exit 1
fi

echo ""
echo "=== Method 1: Port-forward Hubble UI ==="
echo "1. Port-forward Hubble UI:"
echo "   kubectl port-forward -n kube-system svc/hubble-ui 12000:80"
echo ""
echo "2. Access in browser: http://localhost:12000"
echo ""

echo "=== Method 2: Use Hubble CLI (hubble) ==="
echo "1. Install Hubble CLI locally:"
echo "   export HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/master/versions.txt | grep '^hubble:' | cut -d: -f2)"
echo "   curl -L --remote-name-all https://github.com/cilium/hubble/releases/download/\$HUBBLE_VERSION/hubble-linux-amd64.tar.gz{,.sha256sum}"
echo "   sha256sum --check hubble-linux-amd64.tar.gz.sha256sum"
echo "   sudo tar xzvfC hubble-linux-amd64.tar.gz /usr/local/bin"
echo ""
echo "2. Port-forward Hubble Relay:"
echo "   kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""
echo "3. Use Hubble CLI:"
echo "   export HUBBLE_SERVER=localhost:4245"
echo "   hubble observe --follow"
echo ""

echo "=== Method 3: Observe Gateway Traffic ==="
echo "Observe traffic to/from Gateway service:"
echo ""
echo "1. Port-forward Hubble Relay first:"
echo "   kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &"
echo ""
echo "2. Filter by Gateway service:"
GATEWAY_SVC="cilium-gateway-mail-in-a-pods-gateway-http"
echo "   hubble observe --follow --service $GATEWAY_SVC --namespace mailer"
echo ""
echo "3. Filter by pod:"
echo "   hubble observe --follow --pod mail-in-a-pods-mailinabox-8c7678484-wm9l2 --namespace mailer"
echo ""
echo "4. Filter by IP:"
GATEWAY_IP=$(kubectl get svc $GATEWAY_SVC -n mailer -o jsonpath='{.spec.clusterIP}')
echo "   hubble observe --follow --ip $GATEWAY_IP"
echo ""

echo "=== Method 4: Use kubectl exec to run hubble ==="
echo "If hubble CLI is available in a pod:"
echo "   kubectl exec -n kube-system $HUBBLE_RELAY_POD -- hubble observe --follow"
echo ""

echo "=== Method 5: Check Hubble metrics ==="
echo "Hubble exposes Prometheus metrics:"
echo "   kubectl port-forward -n kube-system svc/hubble-metrics 9965:9965"
echo "   curl http://localhost:9965/metrics"
echo ""

echo "=== Quick Test: Observe Gateway Traffic ==="
echo "Making a test request and observing with Hubble..."
echo ""
echo "In one terminal, run:"
echo "   kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""
echo "In another terminal, run:"
echo "   export HUBBLE_SERVER=localhost:4245"
echo "   hubble observe --follow --service $GATEWAY_SVC --namespace mailer"
echo ""
echo "Then make a request:"
echo "   curl http://95.179.135.8/ -H 'Host: mailer4.kuprin.su'"
echo ""

echo "=== Alternative: Use Cilium CLI ==="
echo "If you have cilium CLI installed:"
echo "   cilium connectivity test"
echo "   cilium status"
echo ""

