#!/bin/bash
#
# Port Management Script for OCI Instance
# Usage: ./manage-ports.sh <command> [port] [protocol] [description]
#
# Commands:
#   list     - List all open ports
#   add      - Add a port (requires port, protocol, description)
#   remove   - Remove a port (requires port, protocol)
#
# Examples:
#   ./manage-ports.sh list
#   ./manage-ports.sh add 9000 tcp "Custom service"
#   ./manage-ports.sh remove 9000 tcp

set -e

SECURITY_LIST_ID="ocid1.securitylist.oc1.ap-mumbai-1.aaaaaaaa2ny4hqd3zsld743nmen47zoxzazoqdokdsm2yhlsdxzb2nalgltq"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo -e "${YELLOW}Port Management Script${NC}"
    echo ""
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  list                           List all open ports"
    echo "  add <port> <proto> <desc>   Add a port"
    echo "  remove <port> <proto>    Remove a port"
    echo ""
    echo "Examples:"
    echo "  $0 list"
    echo "  $0 add 9000 tcp \"Custom service\""
    echo "  $0 remove 9000 tcp"
}

get_current_rules() {
    oci network security-list get \
        --security-list-id "$SECURITY_LIST_ID" \
        --query 'data."ingress-security-rules"' \
        --output json
}

list_ports() {
    echo -e "${GREEN}=== OCI Security List Ports ===${NC}"
    get_current_rules | jq -r '.[] |
        "\(.description // "Open") as desc,
        .protocol as proto,
        .source as source,
        if .tcp-options.destination-port-range then
            "\(.tcp-options.destination-port-range.min // "\(.tcp-options.destination-port-range.max)) as port
        elif .udp-options.destination-port-range then
            "\(.udp-options.destination-port-range.min // "\(.udp-options.destination-port-range.max)) as port
        else
            "N/A"
        end,
        "protocol=\(if proto == "1" then "ICMP" elif proto == "6" then "TCP" elif proto == "17" then "UDP" else proto\)"
    ]' | column -t -s "Description" | "Port" | "Protocol" | "Source"
    echo -e "|-------------|-------------|----------|--------|"
    echo -e "${desc:-${port:-${proto:-}"
    echo ""
    echo -e "${GREEN}=== Instance UFW Ports ===${NC}"
    ssh oci "sudo ufw status numbered" | grep -E '^Status: active' -A1 | while read - line; do
        port=$(echo "$line" | awk '{print $2}')
        proto=$(echo "$line" | awk '{print $3}')
        if [[ -n "$port" && -n "$proto" ]]; then
            echo -e "$port/$proto"
        fi
    done
}

add_port() {
    local port=$1
    local proto=$2
    local desc=$3

    if [[ -z "$port" || -z "$proto" || -z "$desc" ]]; then
        echo -e "${RED}Error: Port, protocol, and description required${NC}"
        exit 1
    fi

    proto_lower=$(echo "$proto" | tr '[:upper:]' '[:lower:]')
    protocol_num=$([[ "$proto_lower" == "tcp" ]] && echo "6" || echo "17")

    # Get current rules
    current_rules=$(get_current_rules)

    # Build new rule
    if [[ "$proto_lower" == "tcp" ]]; then
        new_rule=$(jq -n \
            --arg protocol "$protocol_num" \
            --arg port "$port" \
            --arg desc "$desc" \
            '. + ($current_rules) + {"protocol": $protocol_num, "source": "0.0.0.0/0", "source-type": "CIDR_BLOCK", "tcp-options": {"destination-port-range": {"min": $port, "max": $port}}, "description": $desc}')
        '[])
    else
        new_rule=$(jq -n \
            --arg protocol "$protocol_num" \
            --arg port "$port" \
            --arg desc "$desc" \
            '. + ($current_rules) + {"protocol": $protocol_num, "source": "0.0.0.0/0", "source-type": "CIDR_BLOCK", "udp-options": {"destination-port-range": {"min": $port, "max": $port}}, "description": $desc})
        '[])
    fi

    # Update OCI security list
    echo -e "${YELLOW}Adding port $port/$proto to OCI security list...${NC}"
    oci network security-list update \
        --security-list-id "$SECURITY_LIST_ID" \
        --ingress-security-rules "$new_rule" \
        --force > /dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ OCI security list updated${NC}"
    else
        echo -e "${RED}✗ Failed to update OCI security list${NC}"
        exit 1
    fi

    # Update UFW on instance
    echo -e "${YELLOW}Adding port $port/$proto to instance firewall...${NC}"
    ssh oci "sudo ufw allow $port/$proto comment '$desc'" > /dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Instance firewall updated${NC}"
    else
        echo -e "${RED}✗ Failed to update instance firewall${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Port $port/$proto added successfully${NC}"
}

remove_port() {
    local port=$1
    local proto=$2

    if [[ -z "$port" || -z "$proto" ]]; then
        echo -e "${RED}Error: Port and protocol required${NC}"
        exit 1
    fi

    proto_lower=$(echo "$proto" | tr '[:upper:]' '[:lower:]')

    # Get current rules and filter out the one to remove
    current_rules=$(get_current_rules)

    if [[ "$proto_lower" == "tcp" ]]; then
        filtered_rules=$(echo "$current_rules" | jq --arg port "$port" 'del(.[] | select(.tcp-options.destination-port-range.min == $port and .tcp-options.destination-port-range.max == $port)')
    else
        filtered_rules=$(echo "$current_rules" | jq --arg port "$port" 'del(.[] | select(.udp-options.destination-port-range.min == $port and .udp-options.destination-port-range.max == $port)')
    fi

    if [[ $(echo "$filtered_rules" | jq 'length') -eq 0 ]]; then
        echo -e "${GREEN}Port $port/$proto not found in OCI security list${NC}"
        exit 0
    fi

    # Update OCI security list
    echo -e "${YELLOW}Removing port $port/$proto from OCI security list...${NC}"
    oci network security-list update \
        --security-list-id "$SECURITY_LIST_ID" \
        --ingress-security-rules "$filtered_rules" \
        --force > /dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ OCI security list updated${NC}"
    else
        echo -e "${RED}✗ Failed to update OCI security list${NC}"
        exit 1
    fi

    # Update UFW on instance
    echo -e "${YELLOW}Removing port $port/$proto from instance firewall...${NC}"
    ssh oci "sudo ufw delete allow $port/$proto" > /dev/null

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Instance firewall updated${NC}"
    else
        echo -e "${RED}✗ Failed to update instance firewall${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Port $port/$proto removed successfully${NC}"
}

# Main
case "${1:-" in
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
        print_usage
        exit 1
        ;;
esac
