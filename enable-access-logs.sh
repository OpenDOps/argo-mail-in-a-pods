#!/bin/bash
# Enable temporary access logging to debug LoadBalancer traffic
# This patches the NginxProxy to enable access logs temporarily

set -e

export KUBECONFIG=../../MidHub/swapper/argocd.kubeconfig

echo "Enabling access logs for debugging..."
echo ""

# Get the NginxProxy name
NGINX_PROXY=$(kubectl get nginxproxy -n gateway-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "nginx-gateway-fabric-proxy-config")

echo "Using NginxProxy: $NGINX_PROXY"
echo ""

# Check current configuration
echo "Current logging configuration:"
kubectl get nginxproxy $NGINX_PROXY -n gateway-api -o jsonpath='{.spec.logging}' 2>/dev/null || echo "No logging config found"
echo ""
echo ""

# Note: NGINX Gateway Fabric v2.2.1 doesn't support access_log via NginxProxy CRD
# Access logs are hardcoded to 'off'
echo "⚠️  Note: NGINX Gateway Fabric v2.2.1 doesn't support access_log configuration via NginxProxy CRD"
echo "Access logs are hardcoded to 'off' in the generated NGINX config"
echo ""
echo "Alternative debugging methods:"
echo ""
echo "1. Monitor connections in real-time:"
echo "   watch -n 1 'kubectl exec -n mailer \$(kubectl get pods -n mailer -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o jsonpath='{.items[0].metadata.name}') -c nginx -- netstat -an | grep :80 | grep ESTABLISHED | wc -l'"
echo ""
echo "2. Monitor error logs for incoming requests:"
echo "   kubectl logs -f -n mailer -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -c nginx | grep -E 'error|warn|GET|POST'"
echo ""
echo "3. Check LoadBalancer health check:"
echo "   Test health check port on node: kubectl get nodes -o wide"
echo "   Then test: curl http://<NODE_EXTERNAL_IP>:31867/"
echo ""
echo "4. Use tcpdump on the node (if you have access):"
echo "   tcpdump -i any -n port 80 -c 10"
echo ""

