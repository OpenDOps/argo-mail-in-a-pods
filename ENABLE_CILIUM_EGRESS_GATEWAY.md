# Enable Cilium Egress Gateway

## Prerequisites Check

✅ **Kernel Version**: 6.1.0-37-amd64 (requires >= 5.2) - **PASSED**
✅ **Cilium Version**: 1.18.4 - **SUPPORTED**
✅ **Egress Gateway Reconciliation**: Already configured (`egress-gateway-reconciliation-trigger-interval: 1s`)

## Step 1: Enable Egress Gateway in Cilium ConfigMap

```bash
kubectl patch configmap cilium-config -n kube-system --type=merge -p='{"data":{"enable-egress-gateway":"true"}}'
```

## Step 2: Verify CRD Installation

The `CiliumEgressGatewayPolicy` CRD should be installed automatically when Cilium is deployed. Check if it exists:

```bash
kubectl get crd ciliumegressgatewaypolicies.cilium.io
```

If it doesn't exist, you may need to:
1. Check if Cilium was installed via Helm (CRDs should be auto-installed)
2. Manually install the CRD from Cilium's GitHub releases

## Step 3: Restart Cilium DaemonSet

After enabling the feature, restart Cilium pods to apply the configuration:

```bash
kubectl rollout restart daemonset/cilium -n kube-system
```

Wait for all pods to be ready:

```bash
kubectl rollout status daemonset/cilium -n kube-system
```

## Step 4: Label the Egress Gateway Node

Label the node that has IP 95.179.147.120 as an egress gateway node:

```bash
kubectl label node test-main-ams-system-workloads-lrtns-78rtw egress-gateway=true
```

## Step 5: Verify Egress Gateway is Enabled

Check Cilium status on a node:

```bash
kubectl exec -n kube-system $(kubectl get pods -n kube-system -l k8s-app=cilium --field-selector spec.nodeName=test-main-ams-system-workloads-lrtns-78rtw -o jsonpath='{.items[0].metadata.name}') -- cilium status | grep -i egress
```

## Step 6: Create Egress Gateway Policy

Once enabled, create the policy (see `cilium-egress-gateway.yaml`):

```bash
kubectl apply -f addons/mail-in-a-pods/templates/cilium-egress-gateway.yaml
```

## Troubleshooting

### If CRD doesn't exist:

1. **Check Cilium installation method:**
   ```bash
   kubectl get daemonset cilium -n kube-system -o yaml | grep -i helm
   ```

2. **If installed via Helm, check values:**
   ```bash
   helm get values cilium -n kube-system 2>/dev/null || echo "Not installed via Helm"
   ```

3. **Manually install CRD** (if needed):
   ```bash
   # Download from Cilium 1.18.4 release
   kubectl apply -f https://github.com/cilium/cilium/raw/v1.18.4/pkg/k8s/apis/cilium.io/v2/ciliumegressgatewaypolicy.yaml
   ```

### Verify Egress Gateway Feature:

```bash
# Check if egress gateway is mentioned in Cilium config
kubectl get configmap cilium-config -n kube-system -o jsonpath='{.data.enable-egress-gateway}'

# Should output: "true"
```

### Check Cilium Logs:

```bash
kubectl logs -n kube-system -l k8s-app=cilium --tail=100 | grep -i egress
```

## Additional Requirements

For Egress Gateway to work properly, ensure:

1. **BPF Masquerading** (usually enabled by default):
   ```bash
   kubectl get configmap cilium-config -n kube-system -o jsonpath='{.data.enable-bpf-masquerade}'
   ```

2. **Kube-proxy replacement** (usually enabled):
   ```bash
   kubectl get configmap cilium-config -n kube-system -o jsonpath='{.data.kube-proxy-replacement}'
   ```

## Next Steps

After enabling, proceed to create the Egress Gateway Policy for SMTP routing.

