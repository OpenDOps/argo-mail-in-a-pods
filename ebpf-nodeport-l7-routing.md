# eBPF NodePort to L7 Proxy Routing

## Question

Is there eBPF routing from NodePorts to services that does hostname-based routing?

## Answer: No, but eBPF Routes to L7 Proxy

**Cilium eBPF is Layer 4 only** - it cannot inspect HTTP Host headers. However, Cilium can route NodePort traffic to a **Layer 7 proxy** (Envoy), which then does Host header matching.

## Key Finding: L7 Load Balancer Marking

From `cilium-dbg bpf lb list`:

```
0.0.0.0:30510/TCP (0)  0.0.0.0:0 (735) (0) [NodePort, non-routable, l7-load-balancer] (L7LB Proxy Port: 10285)
```

This shows:
- **NodePort 30510** (Cilium Gateway HTTP) is marked as `l7-load-balancer`
- **L7LB Proxy Port: 10285** - This is the Envoy proxy port
- Cilium eBPF routes NodePort 30510 traffic to Envoy on port 10285

## How It Works

### NodePort 30510 (Cilium Gateway)

```
External Request (Node IP:30510)
    ↓
Cilium eBPF (Layer 4 - IP/Port only)
    ↓
Routes to: Envoy Proxy (127.0.0.1:10285)
    ↓
Envoy (Layer 7 - HTTP Host header matching)
    ↓
Virtual Host: mailer3.kuprin.su
    ↓
Backend Service
```

### NodePort 30119 (NGINX Gateway)

```
External Request (Node IP:30119)
    ↓
Cilium eBPF (Layer 4 - IP/Port only)
    ↓
Routes to: NGINX Gateway Pod (10.0.16.191:80)
    ↓
NGINX (Layer 7 - HTTP Host header matching)
    ↓
Backend Service
```

## Why eBPF Cannot Do Hostname-Based Routing

1. **eBPF operates at Layer 4** (TCP/UDP)
   - Can inspect: Source IP, Destination IP, Source Port, Destination Port
   - Cannot inspect: HTTP headers, Host header, URL path

2. **Host header is Layer 7** (HTTP)
   - Requires parsing HTTP protocol
   - eBPF programs cannot parse HTTP headers efficiently

3. **Cilium's approach**:
   - eBPF routes to the correct **service** (Layer 4)
   - The **L7 proxy** (Envoy/NGINX) does Host header matching (Layer 7)

## Why All Three LoadBalancers Hit nginx Gateway Pod

If all three LoadBalancers with `Host: mailer2.kuprin.su` hit the `gateway-test-nginx-nginx` pod, this is **NOT** due to eBPF routing. Possible explanations:

### 1. HTTPRoute Attached to Multiple Gateways

Check if `gateway-test-nginx-http` is attached to multiple gateways:

```bash
kubectl get httproute gateway-test-nginx-http -n mailer -o jsonpath='{.spec.parentRefs[*].name}'
```

If it shows multiple gateway names, that's why.

### 2. LoadBalancer Backend Services

Each LoadBalancer routes to a different NodePort:
- LoadBalancer 185.92.222.27 → NodePort 30510 (Cilium Gateway)
- LoadBalancer 95.179.142.249 → NodePort 30119 (NGINX Gateway)
- LoadBalancer 108.61.117.121 → NodePort 30510 (Cilium Gateway)

But if they all hit the nginx pod, check:
- Are the LoadBalancers configured to route to the same NodePort?
- Is there a shared HTTPRoute?

### 3. Gateway Listener Hostname Restrictions

If Gateway listeners have no hostname restrictions (`hostname: ""`), they accept all hostnames, and the HTTPRoute hostname filter determines routing.

## Verification

### Check eBPF Service Maps

```bash
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $CILIUM_POD -- cilium-dbg bpf lb list | grep -E "(30510|30119)"
```

Look for:
- `l7-load-balancer` marking
- `L7LB Proxy Port` indication
- Backend service IPs

### Check Service Endpoints

```bash
kubectl get endpoints -n mailer
```

Verify which pods each service routes to.

### Check HTTPRoute Parent Refs

```bash
kubectl get httproute -n mailer -o json | jq -r '.items[] | {name: .metadata.name, hostnames: .spec.hostnames, parents: [.spec.parentRefs[]? | .name]}'
```

## Conclusion

**eBPF does NOT do hostname-based routing** - it's Layer 4 only. However:

1. **Cilium eBPF routes NodePort traffic to L7 proxies** (Envoy/NGINX)
2. **L7 proxies do Host header matching**
3. **If all LoadBalancers hit the same pod**, it's due to:
   - Shared HTTPRoute with multiple parentRefs
   - LoadBalancers routing to the same NodePort
   - Gateway listener configuration (no hostname restrictions)

The routing happens at **two layers**:
- **Layer 4 (eBPF)**: Routes to the correct service/proxy
- **Layer 7 (Envoy/NGINX)**: Matches Host headers and routes to backends

