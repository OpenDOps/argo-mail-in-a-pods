# How to Set Health Check Port in Gateway (Helm Setup)

## Overview

For Kubernetes LoadBalancer services with `externalTrafficPolicy: Local`, Kubernetes automatically assigns a health check NodePort. You can also explicitly set it using the `healthCheckNodePort` field.

## Current Configuration

- **Health Check NodePort**: `31049` (auto-assigned)
- **External Traffic Policy**: `Local`
- **Service Type**: `LoadBalancer`

## Method 1: Configure via Helm Values (Recommended)

Since your chart uses a dependency (`mail-in-a-pods` from `oci://ghcr.io/opendops`), you need to check what values the dependency chart accepts. Add health check configuration to your `values.yaml`:

```yaml
mail-in-a-pods:
  gateway:
    enabled: true
    className: "nginx"
    
    # Service configuration for health checks
    service:
      # Health check NodePort (optional - Kubernetes auto-assigns if not specified)
      # Must be in range 30000-32767
      healthCheckNodePort: 31049  # Optional: specify a fixed port
      
      # External traffic policy affects health check behavior
      # "Local" - health checks only work on nodes with pods (requires healthCheckNodePort)
      # "Cluster" - health checks work on any node (no healthCheckNodePort needed)
      externalTrafficPolicy: Local  # or "Cluster"
      
      # Service type
      type: LoadBalancer
      
      # Annotations for LoadBalancer provider (e.g., Vultr)
      annotations:
        # Vultr-specific health check configuration (if supported)
        # service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-path: "/"
        # service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-interval: "10"
```

## Method 2: Patch Service Directly (Quick Test)

If the Helm chart doesn't support health check configuration, you can patch the service:

```bash
# Set a specific health check port (must be 30000-32767)
kubectl patch svc mail-in-a-pods-gateway-nginx -n mailer \
  -p '{"spec":{"healthCheckNodePort":31049}}'

# Or change externalTrafficPolicy to Cluster (no healthCheckNodePort needed)
kubectl patch svc mail-in-a-pods-gateway-nginx -n mailer \
  -p '{"spec":{"externalTrafficPolicy":"Cluster"}}'
```

## Method 3: Create/Modify Service Template

If you have access to the Helm chart templates, modify the Service template:

```yaml
# templates/gateway-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "mail-in-a-pods.fullname" . }}-gateway-nginx
  namespace: {{ .Values.mail-in-a-pods.global.namespace | default "mailer" }}
spec:
  type: LoadBalancer
  externalTrafficPolicy: {{ .Values.mail-in-a-pods.gateway.service.externalTrafficPolicy | default "Local" }}
  {{- if and (eq .Values.mail-in-a-pods.gateway.service.externalTrafficPolicy "Local") .Values.mail-in-a-pods.gateway.service.healthCheckNodePort }}
  healthCheckNodePort: {{ .Values.mail-in-a-pods.gateway.service.healthCheckNodePort }}
  {{- end }}
  selector:
    gateway.networking.k8s.io/gateway-name: {{ include "mail-in-a-pods.fullname" . }}-gateway
  ports:
    - name: http
      port: 80
      targetPort: 80
      protocol: TCP
    # ... other ports
```

## Health Check Port Requirements

1. **Port Range**: Must be between `30000-32767` (NodePort range)
2. **External Traffic Policy**: 
   - `Local`: Requires `healthCheckNodePort` (health checks only on nodes with pods)
   - `Cluster`: No `healthCheckNodePort` needed (health checks on any node)
3. **LoadBalancer Provider**: Some providers (like Vultr) may have additional health check configuration via annotations

## Verify Health Check Configuration

```bash
# Check current health check port
kubectl get svc mail-in-a-pods-gateway-nginx -n mailer \
  -o jsonpath='{.spec.healthCheckNodePort}'

# Check external traffic policy
kubectl get svc mail-in-a-pods-gateway-nginx -n mailer \
  -o jsonpath='{.spec.externalTrafficPolicy}'

# Test health check port (from within cluster)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
HEALTH_PORT=$(kubectl get svc mail-in-a-pods-gateway-nginx -n mailer -o jsonpath='{.spec.healthCheckNodePort}')
curl http://${NODE_IP}:${HEALTH_PORT}/
```

## Recommended Values.yaml Configuration

Add this to your `addons/mail-in-a-pods/values.yaml`:

```yaml
mail-in-a-pods:
  gateway:
    enabled: true
    className: "nginx"
    
    # Service configuration
    service:
      # Health check NodePort (30000-32767)
      # Leave unset to let Kubernetes auto-assign
      healthCheckNodePort: null  # or specify: 31049
      
      # External traffic policy
      # "Local" - preserves source IP, requires pod on node for health checks
      # "Cluster" - may lose source IP, health checks work on any node
      externalTrafficPolicy: Local
      
      type: LoadBalancer
      
      # LoadBalancer provider annotations (Vultr example)
      annotations: {}
        # service.beta.kubernetes.io/vultr-loadbalancer-protocol: "http"
        # service.beta.kubernetes.io/vultr-loadbalancer-healthcheck-path: "/"
```

## Notes

1. **Auto-assignment**: If `healthCheckNodePort` is not specified, Kubernetes automatically assigns a port in the 30000-32767 range
2. **Port conflicts**: Ensure the specified port is not already in use
3. **Provider-specific**: Some LoadBalancer providers (AWS, GCP, Azure, Vultr) may have additional health check configuration via annotations
4. **Readiness Probe**: The pod's readiness probe (`/readyz` on port 8081) is separate from the LoadBalancer health check port

## Troubleshooting

If health checks are failing:

1. **Check if pod is on the node** (for `externalTrafficPolicy: Local`):
   ```bash
   kubectl get pod -n mailer -l gateway.networking.k8s.io/gateway-name=mail-in-a-pods-gateway -o wide
   ```

2. **Test health check port directly**:
   ```bash
   NODE_IP=$(kubectl get pod <pod-name> -n mailer -o jsonpath='{.status.hostIP}')
   HEALTH_PORT=$(kubectl get svc mail-in-a-pods-gateway-nginx -n mailer -o jsonpath='{.spec.healthCheckNodePort}')
   curl -v http://${NODE_IP}:${HEALTH_PORT}/
   ```

3. **Check LoadBalancer provider status** (Vultr console or API)

4. **Consider switching to `Cluster` policy** if health checks fail with `Local`:
   ```yaml
   service:
     externalTrafficPolicy: Cluster
   ```

