#!/bin/bash
# Commands to run directly on the node to monitor connections
# Run these commands on node: test-main-ams-system-workloads-lrtns-78rtw

NODEPORT=32602
HEALTH_PORT=31867

echo "=== Option 1: tcpdump (Best for real-time packet capture) ==="
echo "sudo tcpdump -i any -n port $NODEPORT -v"
echo ""
echo "To see both request and response:"
echo "sudo tcpdump -i any -n port $NODEPORT -A -v"
echo ""
echo ""

echo "=== Option 2: iptables TRACE (Requires monitoring trace output) ==="
echo ""
echo "Step 1: Add trace rule (run once):"
echo "sudo iptables -t raw -A PREROUTING -p tcp --dport $NODEPORT -j TRACE"
echo ""
echo "Step 2: Monitor trace output (keep running):"
echo "sudo dmesg -w | grep TRACE"
echo ""
echo "OR using kernel tracing:"
echo "sudo cat /sys/kernel/debug/tracing/trace_pipe | grep $NODEPORT"
echo ""
echo "Step 3: Remove trace rule when done:"
echo "sudo iptables -t raw -D PREROUTING -p tcp --dport $NODEPORT -j TRACE"
echo ""
echo ""

echo "=== Option 3: Monitor active connections (real-time) ==="
echo "watch -n 1 'ss -tnp | grep $NODEPORT'"
echo ""
echo "OR:"
echo "watch -n 1 'netstat -tnp | grep $NODEPORT'"
echo ""
echo ""

echo "=== Option 4: Monitor all connections to port (with state) ==="
echo "watch -n 1 'ss -tn state established,time-wait,close-wait | grep $NODEPORT'"
echo ""
echo ""

echo "=== Option 5: Monitor iptables rules and counters ==="
echo "sudo iptables -t nat -L -n -v | grep $NODEPORT"
echo "sudo iptables -t filter -L -n -v | grep $NODEPORT"
echo ""
echo ""

echo "=== Option 6: Monitor kube-proxy connections ==="
echo "sudo ss -tnp | grep kube-proxy"
echo "sudo netstat -tnp | grep kube-proxy"
echo ""
echo ""

echo "=== Recommended: Use tcpdump for best visibility ==="
echo "Run this in one terminal:"
echo "  sudo tcpdump -i any -n port $NODEPORT -A -v"
echo ""
echo "Then in another terminal, make your request:"
echo "  curl http://95.179.147.120:$NODEPORT/ -H 'Host: mailer4.kuprin.su'"
echo ""
echo "You'll see all packets including:"
echo "  - SYN (connection attempt)"
echo "  - Data packets"
echo "  - RST (connection reset)"
echo "  - FIN (connection close)"

