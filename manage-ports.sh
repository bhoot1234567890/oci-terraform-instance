#!/bin/bash
# Port Management Script for OCI Instance
# Usage: ./manage-ports.sh <command> [options]
#
# Commands:
#   list     - List all open ports
#   add      - Add a port (requires port, protocol, description)
#   remove   - Remove a port (requires port, protocol)
#
# Note: Oracle Linux has a REJECT rule in iptables that blocks traffic
# before UFW rules. This script handles all three firewall layers:
# 1. OCI Security List (cloud firewall)
# 2. iptables (kernel firewall - has priority over UFW)
# 3. UFW (user-friendly firewall frontend)

SECURITY_LIST_ID="ocid1.securitylist.oc1.ap-mumbai-1.aaaaaaaa2ny4hqd3zsld743nmen47zoxzazoqdokdsm2yhlsdxzb2nalgltq"

show_usage() {
    echo "Port Management Script for OCI Instance"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                           List all open ports"
    echo "  add <port> <proto> <desc>     Add a port (tcp/udp)"
    echo "  remove <port> <proto>         Remove a port"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 add 9000 tcp 'Custom service'"
    echo "  $0 remove 9000 tcp"
    echo ""
    echo "Note: Updates OCI Security List, iptables, and UFW"
    exit 1
}

list_ports() {
    echo "=== OCI Security List Ports ==="
    echo ""
    oci network security-list get \
        --security-list-id "$SECURITY_LIST_ID" \
        --query 'data."ingress-security-rules"' \
        --output json 2>/dev/null | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
    for r in data:
        if r.get("protocol") in ["6", "17"]:
            desc = r.get("description") or "N/A"
            proto = "TCP" if r["protocol"] == "6" else "UDP"
            tcp = r.get("tcp-options", {})
            udp = r.get("udp-options", {})
            if tcp and "destination-port-range" in tcp:
                port = tcp["destination-port-range"].get("min", "N/A")
            elif udp and "destination-port-range" in udp:
                port = udp["destination-port-range"].get("min", "N/A")
            else:
                port = "N/A"
            print(f"  {desc:<30} | {proto:<5} | {port:<8}")
except Exception as e:
    print(f"Error: {e}")
' || echo "  Unable to list OCI ports"
    echo ""
    echo "=== Instance iptables Ports (before REJECT) ==="
    ssh oci "sudo iptables -L INPUT -n --line-numbers 2>/dev/null | grep -E 'ACCEPT.*dpt:' | head -20" || echo "  Unable to connect"
    echo ""
    echo "=== Instance UFW Ports ==="
    ssh oci "sudo ufw status numbered 2>/dev/null | head -20" || echo "  Unable to connect"
}

add_port() {
    local port="$1"
    local proto="$2"
    local desc="$3"

    if [ -z "$port" ] || [ -z "$proto" ] || [ -z "$desc" ]; then
        echo "Error: Port, protocol, and description required"
        exit 1
    fi

    proto_lower=$(echo "$proto" | tr '[:upper:]' '[:lower:]')
    protocol_num="6"
    [ "$proto_lower" = "udp" ] && protocol_num="17"

    # 1. Update OCI Security List
    echo "Adding port $port/$proto to OCI security list..."
    current=$(oci network security-list get \
        --security-list-id "$SECURITY_LIST_ID" \
        --query 'data."ingress-security-rules"' \
        --output json 2>/dev/null)

    if [ -z "$current" ]; then
        echo "Error: Failed to get current rules"
        exit 1
    fi

    if [ "$proto_lower" = "tcp" ]; then
        new_rules=$(echo "$current" | python3 -c "
import sys, json
rules = json.load(sys.stdin)
new = {'protocol': '$protocol_num', 'source': '0.0.0.0/0', 'source-type': 'CIDR_BLOCK', 'tcp-options': {'destination-port-range': {'min': $port, 'max': $port}}, 'description': '$desc'}
rules.append(new)
print(json.dumps(rules))
")
    else
        new_rules=$(echo "$current" | python3 -c "
import sys, json
rules = json.load(sys.stdin)
new = {'protocol': '$protocol_num', 'source': '0.0.0.0/0', 'source-type': 'CIDR_BLOCK', 'udp-options': {'destination-port-range': {'min': $port, 'max': $port}}, 'description': '$desc'}
rules.append(new)
print(json.dumps(rules))
")
    fi

    oci network security-list update \
        --security-list-id "$SECURITY_LIST_ID" \
        --ingress-security-rules "$new_rules" \
        --force > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "✓ OCI updated"
    else
        echo "✗ OCI update failed"
        exit 1
    fi

    # 2. Update iptables (insert before REJECT rule)
    echo "Adding port $port/$proto to iptables..."
    if [ "$proto_lower" = "tcp" ]; then
        ssh oci "sudo iptables -I INPUT 5 -p tcp --dport $port -j ACCEPT" > /dev/null 2>&1
    else
        ssh oci "sudo iptables -I INPUT 5 -p udp --dport $port -j ACCEPT" > /dev/null 2>&1
    fi

    if [ $? -eq 0 ]; then
        echo "✓ iptables updated"
    else
        echo "✗ iptables update failed"
        exit 1
    fi

    # 3. Update UFW
    echo "Adding port $port/$proto to UFW..."
    ssh oci "sudo ufw allow $port/$proto comment '$desc'" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "✓ UFW updated"
    else
        echo "✗ UFW update failed"
        exit 1
    fi

    # 4. Save iptables rules persistently
    ssh oci "sudo mkdir -p /etc/iptables 2>/dev/null; sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null 2>&1" || echo "  (iptables-persistent not installed, rules may not persist)"

    echo "✓ Port $port/$proto added successfully"
}

remove_port() {
    local port="$1"
    local proto="$2"

    if [ -z "$port" ] || [ -z "$proto" ]; then
        echo "Error: Port and protocol required"
        exit 1
    fi

    proto_lower=$(echo "$proto" | tr '[:upper:]' '[:lower:]')

    # 1. Update OCI Security List
    echo "Removing port $port/$proto from OCI security list..."
    current=$(oci network security-list get \
        --security-list-id "$SECURITY_LIST_ID" \
        --query 'data."ingress-security-rules"' \
        --output json 2>/dev/null)

    if [ -z "$current" ]; then
        echo "Error: Failed to get current rules"
        exit 1
    fi

    if [ "$proto_lower" = "tcp" ]; then
        new_rules=$(echo "$current" | python3 -c "
import sys, json
rules = json.load(sys.stdin)
filtered = []
for r in rules:
    tcp = r.get('tcp-options', {})
    if tcp and 'destination-port-range' in tcp:
        min_p = tcp['destination-port-range'].get('min')
        max_p = tcp['destination-port-range'].get('max')
        if min_p == $port and max_p == $port:
            continue
    filtered.append(r)
print(json.dumps(filtered))
")
    else
        new_rules=$(echo "$current" | python3 -c "
import sys, json
rules = json.load(sys.stdin)
filtered = []
for r in rules:
    udp = r.get('udp-options', {})
    if udp and 'destination-port-range' in udp:
        min_p = udp['destination-port-range'].get('min')
        max_p = udp['destination-port-range'].get('max')
        if min_p == $port and max_p == $port:
            continue
    filtered.append(r)
print(json.dumps(filtered))
")
    fi

    oci network security-list update \
        --security-list-id "$SECURITY_LIST_ID" \
        --ingress-security-rules "$new_rules" \
        --force > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "✓ OCI updated"
    else
        echo "✗ OCI update failed"
        exit 1
    fi

    # 2. Update iptables
    echo "Removing port $port/$proto from iptables..."
    if [ "$proto_lower" = "tcp" ]; then
        ssh oci "sudo iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null" || echo "  (Rule not found or already removed)"
    else
        ssh oci "sudo iptables -D INPUT -p udp --dport $port -j ACCEPT 2>/dev/null" || echo "  (Rule not found or already removed)"
    fi

    echo "✓ iptables updated"

    # 3. Update UFW
    echo "Removing port $port/$proto from UFW..."
    ssh oci "sudo ufw delete allow $port/$proto" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "✓ UFW updated"
    else
        echo "✗ UFW update failed"
    fi

    # 4. Save iptables rules persistently
    ssh oci "sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null 2>&1" || true

    echo "✓ Port $port/$proto removed successfully"
}

# Main
case "${1:-}" in
    list)
        list_ports
        ;;
    add)
        add_port "$2" "$3" "$4"
        ;;
    remove)
        remove_port "$2" "$3"
        ;;
    *)
        show_usage
        ;;
esac
