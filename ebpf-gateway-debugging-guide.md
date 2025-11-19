# Cilium Gateway eBPF Routing Debugging Guide

## Overview

Cilium Gateway uses a combination of:
1. **eBPF programs** (handled by Cilium agent) - for L4 load balancing
2. **Envoy proxy** (cilium-envoy pods) - for L7 HTTP routing
3. **BPF maps** - for service and backend tracking

## Architecture

```
Client Request
    ↓
LoadBalancer IP (108.61.117.121)
    ↓
Cilium eBPF (L4 Load Balancing)
    ↓
Envoy Proxy (L7 HTTP Routing)
    ↓
Backend Service (mail-in-a-pods-statics-server)
```

## Method 1: Cilium CLI (Inside Pod)

### Check Cilium Status

```bash
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $CILIUM_POD -- cilium status
```

### Check Service Backend

```bash
GATEWAY_SVC_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.spec.clusterIP}')
kubectl exec -n kube-system $CILIUM_POD -- cilium service list | grep $GATEWAY_SVC_IP
```

### Check Service Details

```bash
kubectl exec -n kube-system $CILIUM_POD -- cilium service get $GATEWAY_SVC_IP
```

### Check BPF Load Balancer Maps

```bash
# List all services in BPF map
kubectl exec -n kube-system $CILIUM_POD -- cilium bpf lb list

# Filter by service IP
kubectl exec -n kube-system $CILIUM_POD -- cilium bpf lb list | grep $GATEWAY_SVC_IP

# Filter by LoadBalancer IP
GATEWAY_LB_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
kubectl exec -n kube-system $CILIUM_POD -- cilium bpf lb list | grep $GATEWAY_LB_IP
```

### Check Endpoint Maps

```bash
kubectl exec -n kube-system $CILIUM_POD -- cilium bpf endpoint list
```

## Method 2: Envoy Configuration (HTTP Routing)

Cilium Gateway uses Envoy for HTTP routing. The eBPF layer handles L4, Envoy handles L7.

### Port-Forward to Envoy Admin

```bash
ENVOY_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium-envoy -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n kube-system $ENVOY_POD 15000:15000
```

### Get Listener Configuration

```bash
curl http://localhost:15000/listeners | jq '.listener_statuses[] | select(.name | contains("mail-in-a-pods-gateway-test"))'
```

### Get Route Configuration

```bash
curl http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test"))'
```

### Get Virtual Hosts (HTTPRoute Configuration)

```bash
curl -s http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test")) | .active_state.listener.filter_chains[] | select(.filters[].name == "envoy.filters.network.http_connection_manager") | .filters[0].typed_config.route_config.virtual_hosts[]'
```

### Get Cluster Configuration (Backend Services)

```bash
curl http://localhost:15000/clusters | grep -i mailer
```

### Get Stats

```bash
curl http://localhost:15000/stats | grep -i gateway
```

### Full Config Dump

```bash
curl http://localhost:15000/config_dump > envoy-config.json
jq '.' envoy-config.json | less
```

## Method 3: Hubble (Flow Observation)

Hubble shows actual network flows through eBPF.

### Port-Forward Hubble Relay

```bash
kubectl port-forward -n kube-system svc/hubble-relay 4245:80
export HUBBLE_SERVER=localhost:4245
```

### Observe Traffic to Gateway

```bash
# By service IP
GATEWAY_SVC_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.spec.clusterIP}')
hubble observe --ip $GATEWAY_SVC_IP --follow --last 50

# By LoadBalancer IP
GATEWAY_LB_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
hubble observe --ip $GATEWAY_LB_IP --follow --last 50

# By service name
hubble observe --service cilium-gateway-mail-in-a-pods-gateway-test --namespace mailer --follow --last 50
```

### Filter by Protocol and Port

```bash
hubble observe --protocol tcp --port 80 --namespace mailer --follow --last 50
```

### Filter by HTTP

```bash
hubble observe --protocol http --namespace mailer --follow --last 50
```

## Method 4: BPF Tools (Low-Level)

### Check BPF Programs

```bash
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system $CILIUM_POD -- bpftool prog list
```

### Check BPF Maps

```bash
kubectl exec -n kube-system $CILIUM_POD -- bpftool map list
```

### Dump Service Map

```bash
kubectl exec -n kube-system $CILIUM_POD -- bpftool map dump name cilium_lb4_services_v2
```

### Dump Backend Map

```bash
kubectl exec -n kube-system $CILIUM_POD -- bpftool map dump name cilium_lb4_backends_v2
```

### Trace BPF Program Execution

```bash
kubectl exec -n kube-system $CILIUM_POD -- bpftool prog tracelog
```

## Method 5: Kubernetes Resources

### Check Gateway Status

```bash
kubectl get gateway mail-in-a-pods-gateway-test -n mailer -o yaml | grep -A 50 'status:'
```

### Check HTTPRoute Status

```bash
kubectl get httproute -n mailer -o yaml | grep -A 30 'status:'
```

### Check Service Endpoints

```bash
kubectl get endpoints cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o yaml
```

### Check Cilium LoadBalancer IP Pool

```bash
kubectl get ciliumloadbalancerippool -o yaml
```

## Method 6: Network Tracing

### Check iptables (if kube-proxy still running)

```bash
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
GATEWAY_SVC_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.spec.clusterIP}')
kubectl exec -n kube-system $CILIUM_POD -- iptables -t nat -L -n -v | grep $GATEWAY_SVC_IP
```

### Check Cilium Network Policies

```bash
kubectl get cnp,ccnp -A
```

### Check Cilium Endpoints

```bash
kubectl get cep -A | grep mailer
```

## Debugging mailer3.kuprin.su Issue

### Step 1: Check Envoy Route Configuration

```bash
ENVOY_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium-envoy -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n kube-system $ENVOY_POD 15000:15000 &
sleep 2

# Get virtual hosts (HTTPRoute hostname matching)
curl -s http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test")) | .active_state.listener.filter_chains[] | select(.filters[].name == "envoy.filters.network.http_connection_manager") | .filters[0].typed_config.route_config.virtual_hosts[] | {name: .name, domains: .domains, routes: .routes[].match}'
```

### Step 2: Check Filter Chain Matching

```bash
curl -s http://localhost:15000/config_dump | jq '.configs[2].dynamic_listeners[] | select(.name | contains("mail-in-a-pods-gateway-test")) | .active_state.listener.filter_chains[] | {filter_chain_match: .filter_chain_match, filters: [.filters[] | {name: .name}]}'
```

### Step 3: Make Test Request and Observe

```bash
# Terminal 1: Observe with Hubble
export HUBBLE_SERVER=localhost:4245
GATEWAY_SVC_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.spec.clusterIP}')
hubble observe --ip $GATEWAY_SVC_IP --follow --last 10

# Terminal 2: Make request
GATEWAY_LB_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -v http://$GATEWAY_LB_IP/ -H 'Host: mailer3.kuprin.su'
```

### Step 4: Check Envoy Logs

```bash
ENVOY_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium-envoy -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n kube-system $ENVOY_POD --tail=100 | grep -i "mailer3\|gateway\|route"
```

## Understanding the Flow

1. **L4 (eBPF)**: Cilium eBPF programs handle LoadBalancer IP → Service IP routing
   - Check with: `cilium bpf lb list`
   - Observe with: `hubble observe --ip <LB_IP>`

2. **L7 (Envoy)**: Envoy handles HTTP routing based on HTTPRoute configuration
   - Check with: `curl http://localhost:15000/config_dump`
   - This is where hostname matching happens

3. **Backend**: Envoy routes to backend service
   - Check with: `curl http://localhost:15000/clusters`

## Common Issues

### Issue: Route not working

1. Check Envoy listener is configured: `curl http://localhost:15000/listeners`
2. Check virtual hosts match hostname: `curl http://localhost:15000/config_dump | jq '...virtual_hosts[]'`
3. Check backend cluster is healthy: `curl http://localhost:15000/clusters | grep mailer`

### Issue: LoadBalancer IP not routing

1. Check BPF service map: `cilium bpf lb list | grep <LB_IP>`
2. Check service backend: `cilium service get <SVC_IP>`
3. Observe with Hubble: `hubble observe --ip <LB_IP>`

### Issue: Hostname not matching

1. Check Envoy virtual hosts: `curl http://localhost:15000/config_dump | jq '...virtual_hosts[].domains'`
2. Check HTTPRoute hostname: `kubectl get httproute -n mailer -o yaml | grep hostnames`
3. Check Gateway listener hostname: `kubectl get gateway -n mailer -o yaml | grep hostname`

## Quick Reference

```bash
# All-in-one debugging script
./debug-cilium-ebpf-gateway.sh

# Quick service check
CILIUM_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')
GATEWAY_SVC_IP=$(kubectl get svc cilium-gateway-mail-in-a-pods-gateway-test -n mailer -o jsonpath='{.spec.clusterIP}')
kubectl exec -n kube-system $CILIUM_POD -- cilium service list | grep $GATEWAY_SVC_IP

# Quick Envoy check
ENVOY_POD=$(kubectl get pods -n kube-system -l k8s-app=cilium-envoy -o jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n kube-system $ENVOY_POD 15000:15000 &
sleep 2
curl http://localhost:15000/listeners | jq '.listener_statuses[] | select(.name | contains("mail-in-a-pods-gateway-test"))'
```

