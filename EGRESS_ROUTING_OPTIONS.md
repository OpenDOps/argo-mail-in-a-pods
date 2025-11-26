# Options for Routing Egress SMTP via Node 95.179.147.120

## Option 1: Node-level iptables Source NAT (Recommended - No additional pods)

Configure iptables on the target node (95.179.147.120) to SNAT traffic from the mailer namespace.

**On the target node (`test-main-ams-system-workloads-lrtns-78rtw`):**

```bash
# SSH to the node
# Add iptables rule to SNAT SMTP traffic from mailer namespace pods
iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -p tcp --dport 25 -j SNAT --to-source 95.179.147.120

# Make it persistent (add to /etc/iptables/rules.v4 or use a systemd service)
```

**Pros:**
- No additional pods
- Works at network level
- Minimal overhead

**Cons:**
- Requires node-level access
- Manual configuration
- Need to track pod IP ranges

## Option 2: Cilium Egress Gateway (If enabled)

Cilium 1.18.4 supports egress gateway. Enable and configure:

```bash
# Enable egress gateway in Cilium config
kubectl patch configmap cilium-config -n kube-system --type=merge -p='{"data":{"enable-egress-gateway":"true"}}'

# Restart Cilium pods
kubectl rollout restart daemonset/cilium -n kube-system
```

Then create a CiliumEgressGatewayPolicy (if CRD exists):

```yaml
apiVersion: cilium.io/v2
kind: CiliumEgressGatewayPolicy
metadata:
  name: smtp-egress
  namespace: mailer
spec:
  selectors:
  - podSelector:
      matchLabels:
        app: mailinabox
  destinationCIDRs:
  - "0.0.0.0/0"  # All external destinations
  egressGateway:
    nodeSelector:
      matchLabels:
        kubernetes.io/hostname: test-main-ams-system-workloads-lrtns-78rtw
    egressIP: "95.179.147.120"
```

**Pros:**
- Kubernetes-native
- Automatic pod IP tracking
- Policy-based

**Cons:**
- Requires Cilium egress gateway enabled
- May need Cilium upgrade/configuration

## Option 3: NetworkPolicy + Service with ExternalIP

Use a Service with ExternalIP on the target node:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: smtp-egress
  namespace: mailer
spec:
  type: ExternalName
  externalName: 95.179.147.120
  ports:
  - port: 25
```

Then use iptables on source nodes to route via this service.

**Pros:**
- Kubernetes-native service
- Can be managed declaratively

**Cons:**
- Still requires node-level iptables
- ExternalName doesn't help with source IP

## Option 4: Lightweight SMTP Proxy (smtp-sink or similar)

Use a minimal SMTP proxy instead of full Postfix:

```yaml
# Use a lightweight SMTP forwarder like:
# - smtp-sink (very minimal)
# - msmtp (mail client as relay)
# - ssmtp (simple sendmail)
```

**Pros:**
- Lighter than Postfix
- Still handles SMTP properly

**Cons:**
- Still an additional pod
- May not handle all SMTP features

## Option 5: Node-level routing with iproute2

Configure routing on nodes to use specific source IP:

```bash
# On target node, add route for mailer namespace
ip route add 10.0.2.0/24 via <gateway> src 95.179.147.120

# Or use policy-based routing
ip rule add from 10.0.2.0/24 lookup 100
ip route add default via <gateway> src 95.179.147.120 table 100
```

**Pros:**
- No additional pods
- Network-level solution

**Cons:**
- Complex routing setup
- Requires node access
- May conflict with CNI

## Recommendation

**Best option: Node-level iptables SNAT (Option 1)** if you have node access, or **Cilium Egress Gateway (Option 2)** if it's available.

For immediate implementation without node access, the Postfix relay (from smtp-relay.yaml) is the most reliable option.

