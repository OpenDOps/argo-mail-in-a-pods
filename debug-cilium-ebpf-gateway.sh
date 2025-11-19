#!/bin/bash
# Script to debug Cilium Gateway eBPF routing
# Shows eBPF programs, maps, and routing configuration

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="mailer"
GATEWAY_NAME="mail-in-a-pods-gateway-test"
GATEWAY_SVC="cilium-gateway-${GATEWAY_NAME}"

echo "=== Cilium Gateway eBPF Debugging Guide ==="
echo ""

# Get Cilium pod
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -z "$CILIUM_POD" ]; then
    echo "❌ Cilium pod not found"
    exit 1
fi

echo "Cilium Pod: $CILIUM_POD"
echo ""

# Get Gateway service info
GATEWAY_SVC_IP=$(kubectl get svc $GATEWAY_SVC -n $NAMESPACE -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
GATEWAY_LB_IP=$(kubectl get svc $GATEWAY_SVC -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

echo "Gateway Service IP: ${GATEWAY_SVC_IP:-N/A}"
echo "Gateway LoadBalancer IP: ${GATEWAY_LB_IP:-N/A}"
echo ""

echo "=== Method 1: Cilium CLI (Inside Pod) ==="
echo ""
echo "1. Check Cilium status:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium status"
echo ""
echo "2. Check service backend:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium service list | grep $GATEWAY_SVC_IP"
echo ""
echo "3. Check service backend details:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium service get $GATEWAY_SVC_IP"
echo ""
echo "4. Check BPF maps for service:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium bpf lb list | grep $GATEWAY_SVC_IP"
echo ""
echo "5. Check BPF maps for LoadBalancer:"
if [ -n "$GATEWAY_LB_IP" ]; then
    echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium bpf lb list | grep $GATEWAY_LB_IP"
fi
echo ""
echo "6. Check endpoint maps:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium bpf endpoint list"
echo ""
echo "7. Check policy maps:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- cilium bpf policy list"
echo ""

echo "=== Method 2: Envoy Configuration (HTTP Routing) ==="
echo ""
echo "Cilium Gateway uses Envoy for HTTP routing. Check Envoy config:"
echo ""
ENVOY_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium-envoy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$ENVOY_POD" ]; then
    echo "Envoy Pod: $ENVOY_POD"
    echo ""
    echo "1. Port-forward to Envoy admin:"
    echo "   kubectl port-forward -n kube-system $ENVOY_POD 15000:15000"
    echo ""
    echo "2. Get listener configuration:"
    echo "   curl http://localhost:15000/listeners | jq '.listener_statuses[] | select(.name | contains(\"$GATEWAY_NAME\"))'"
    echo ""
    echo "3. Get route configuration:"
    echo "   curl http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains(\"$GATEWAY_NAME\"))'"
    echo ""
    echo "4. Get cluster configuration:"
    echo "   curl http://localhost:15000/clusters | grep -i mailer"
    echo ""
    echo "5. Get stats:"
    echo "   curl http://localhost:15000/stats | grep -i gateway"
    echo ""
    echo "6. Get full config dump:"
    echo "   curl http://localhost:15000/config_dump > envoy-config.json"
    echo ""
else
    echo "❌ Envoy pod not found"
fi
echo ""

echo "=== Method 3: Hubble (Flow Observation) ==="
echo ""
echo "1. Port-forward Hubble Relay:"
echo "   kubectl port-forward -n kube-system svc/hubble-relay 4245:80"
echo ""
echo "2. Set HUBBLE_SERVER:"
echo "   export HUBBLE_SERVER=localhost:4245"
echo ""
echo "3. Observe traffic to Gateway:"
if [ -n "$GATEWAY_SVC_IP" ]; then
    echo "   hubble observe --ip $GATEWAY_SVC_IP --follow --last 50"
fi
if [ -n "$GATEWAY_LB_IP" ]; then
    echo "   hubble observe --ip $GATEWAY_LB_IP --follow --last 50"
fi
echo ""
echo "4. Filter by service:"
echo "   hubble observe --service $GATEWAY_SVC --namespace $NAMESPACE --follow --last 50"
echo ""
echo "5. Filter by protocol and port:"
echo "   hubble observe --protocol tcp --port 80 --namespace $NAMESPACE --follow --last 50"
echo ""

echo "=== Method 4: BPF Tools (Low-Level) ==="
echo ""
echo "1. Check BPF programs loaded:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- bpftool prog list"
echo ""
echo "2. Check BPF maps:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- bpftool map list"
echo ""
echo "3. Check specific service map:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- bpftool map dump name cilium_lb4_services_v2"
echo ""
echo "4. Check backend map:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- bpftool map dump name cilium_lb4_backends_v2"
echo ""
echo "5. Trace BPF program execution:"
echo "   kubectl exec -n kube-system $CILIUM_POD -- bpftool prog tracelog"
echo ""

echo "=== Method 5: Kubernetes Resources ==="
echo ""
echo "1. Check Gateway status:"
echo "   kubectl get gateway $GATEWAY_NAME -n $NAMESPACE -o yaml | grep -A 50 'status:'"
echo ""
echo "2. Check HTTPRoute status:"
echo "   kubectl get httproute -n $NAMESPACE -o yaml | grep -A 30 'status:'"
echo ""
echo "3. Check Service endpoints:"
echo "   kubectl get endpoints $GATEWAY_SVC -n $NAMESPACE -o yaml"
echo ""
echo "4. Check Cilium LoadBalancer IP Pool:"
echo "   kubectl get ciliumloadbalancerippool -o yaml"
echo ""

echo "=== Method 6: Network Tracing ==="
echo ""
echo "1. Check iptables rules (if kube-proxy is still running):"
echo "   kubectl exec -n kube-system $CILIUM_POD -- iptables -t nat -L -n -v | grep $GATEWAY_SVC_IP"
echo ""
echo "2. Check Cilium network policies:"
echo "   kubectl get cnp,ccnp -A"
echo ""
echo "3. Check Cilium endpoints:"
echo "   kubectl get cep -A | grep $NAMESPACE"
echo ""

echo "=== Quick Debugging Commands ==="
echo ""
echo "Run these to quickly check Gateway routing:"
echo ""
echo "# 1. Check service backend"
echo "kubectl exec -n kube-system $CILIUM_POD -- cilium service list | grep -E 'SVC_IP|$GATEWAY_SVC_IP'"
echo ""
echo "# 2. Check if LoadBalancer IP is in BPF map"
if [ -n "$GATEWAY_LB_IP" ]; then
    echo "kubectl exec -n kube-system $CILIUM_POD -- cilium bpf lb list | grep $GATEWAY_LB_IP"
fi
echo ""
echo "# 3. Check Envoy listeners (if port-forwarded)"
echo "curl -s http://localhost:15000/listeners | jq '.listener_statuses[] | select(.name | contains(\"$GATEWAY_NAME\"))'"
echo ""
echo "# 4. Observe traffic with Hubble"
echo "export HUBBLE_SERVER=localhost:4245"
if [ -n "$GATEWAY_SVC_IP" ]; then
    echo "hubble observe --ip $GATEWAY_SVC_IP --follow --last 20"
fi
echo ""

echo "=== Troubleshooting mailer3.kuprin.su Issue ==="
echo ""
echo "To debug why mailer3.kuprin.su doesn't work:"
echo ""
echo "1. Check Envoy route configuration:"
echo "   kubectl port-forward -n kube-system $ENVOY_POD 15000:15000 &"
echo "   sleep 2"
echo "   curl -s http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains(\"$GATEWAY_NAME\")) | .active_state.listener.filter_chains[] | select(.filters[].name == \"envoy.filters.network.http_connection_manager\") | .filters[0].typed_config.route_config.virtual_hosts[]'"
echo ""
echo "2. Check if hostname matching is configured:"
echo "   curl -s http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains(\"$GATEWAY_NAME\")) | .active_state.listener.filter_chains[] | .filter_chain_match'"
echo ""
echo "3. Make a test request and observe with Hubble:"
echo "   hubble observe --ip $GATEWAY_SVC_IP --follow --last 10 &"
echo "   curl -v http://$GATEWAY_LB_IP/ -H 'Host: mailer3.kuprin.su'"
echo ""

