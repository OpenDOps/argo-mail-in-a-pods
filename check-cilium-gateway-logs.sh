#!/bin/bash
# Check Cilium Gateway request/response logs
# Cilium Gateway uses Envoy proxy running in cilium-envoy pods

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig
NAMESPACE="kube-system"
LB_IP="95.179.135.8"
HOSTNAME="mailer4.kuprin.su"

echo "=== Cilium Gateway Logging Guide ==="
echo ""
echo "Cilium Gateway Architecture:"
echo "- Cilium Gateway uses Envoy proxy (not dedicated pods in app namespace)"
echo "- Envoy runs in 'cilium-envoy-*' pods in kube-system namespace"
echo "- The service endpoint (192.192.192.192:9999) is a virtual IP managed by Cilium"
echo "- Traffic is processed by Envoy proxies via eBPF"
echo ""
echo "=== Method 1: Envoy Access Logs (if enabled) ==="
echo "Check Envoy pod logs for HTTP requests:"
echo ""
for pod in $(kubectl get pods -n $NAMESPACE -l k8s-app=cilium-envoy -o jsonpath='{.items[*].metadata.name}'); do
  echo "  kubectl logs -n $NAMESPACE $pod --tail=50 | grep -E 'GET|POST|PUT|DELETE|HTTP'"
done
echo ""
echo "=== Method 2: Envoy Admin Interface (Best for real-time monitoring) ==="
echo "1. Port-forward to Envoy admin interface:"
ENVOY_POD=$(kubectl get pods -n $NAMESPACE -l k8s-app=cilium-envoy -o jsonpath='{.items[0].metadata.name}')
echo "   kubectl port-forward -n $NAMESPACE $ENVOY_POD 15000:15000"
echo ""
echo "2. Access Envoy admin in browser: http://localhost:15000"
echo ""
echo "3. Useful endpoints:"
echo "   - Access logs: http://localhost:15000/logging?level=debug"
echo "   - Stats: http://localhost:15000/stats"
echo "   - Listeners: http://localhost:15000/listeners"
echo "   - Clusters: http://localhost:15000/clusters"
echo "   - Config dump: http://localhost:15000/config_dump"
echo ""
echo "4. Enable access logs via admin API:"
echo "   curl -X POST 'http://localhost:15000/logging?level=debug'"
echo "   curl -X POST 'http://localhost:15000/logging?http=debug'"
echo ""
echo "=== Method 3: Cilium Agent Logs ==="
echo "Cilium agent logs may contain gateway-related info:"
echo "  kubectl logs -n $NAMESPACE -l k8s-app=cilium --tail=50 | grep -i gateway"
echo ""
echo "=== Method 4: Envoy Stats (via admin interface) ==="
echo "Get request counts and metrics:"
echo "  curl http://localhost:15000/stats | grep -E 'http|downstream|upstream' | grep -E 'mailer4|mail-in-a-pods'"
echo ""
echo "=== Method 5: Test Request and Monitor Logs ==="
echo "1. In one terminal, tail Envoy logs:"
echo "   kubectl logs -f -n $NAMESPACE -l k8s-app=cilium-envoy | grep -E 'GET|POST|mailer4'"
echo ""
echo "2. In another terminal, make a test request:"
echo "   curl -v http://${LB_IP}/ -H 'Host: ${HOSTNAME}'"
echo ""
echo "=== Method 6: Check Envoy Configuration ==="
echo "Verify gateway listeners are configured:"
echo "  kubectl port-forward -n $NAMESPACE $ENVOY_POD 15000:15000 &"
echo "  sleep 2"
echo "  curl http://localhost:15000/listeners | jq '.listener_statuses[] | select(.name | contains(\"mail-in-a-pods-gateway\"))'"
echo ""
echo "=== Current Envoy Pods ==="
kubectl get pods -n $NAMESPACE -l k8s-app=cilium-envoy -o wide
echo ""
echo "=== Quick Test: Check if any Envoy pod has recent activity ==="
echo "Checking last 10 lines of each Envoy pod:"
for pod in $(kubectl get pods -n $NAMESPACE -l k8s-app=cilium-envoy -o jsonpath='{.items[*].metadata.name}'); do
  echo ""
  echo "--- $pod ---"
  kubectl logs -n $NAMESPACE $pod --tail=5 2>&1 | tail -3
done

