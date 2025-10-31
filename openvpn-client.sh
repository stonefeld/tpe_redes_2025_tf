#!/bin/bash

# OpenVPN Client Gateway Setup (LAN B)

set -e

# Values injected via user data template
REMOTE_CIDR="${remote_cidr}"

echo "==============================================="
echo "OpenVPN Client Gateway Setup"
echo "Remote (server) CIDR: $REMOTE_CIDR"
echo "==============================================="

echo "Updating system packages..."
apt-get update
apt-get upgrade -y

echo "Installing OpenVPN and helpers..."
DEBIAN_FRONTEND=noninteractive apt-get install -y openvpn python3 iptables-persistent || true

# Enable IP forwarding (gateway)
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p || true

# Basic forwarding rules (no NAT here by default)
iptables -A FORWARD -i tun+ -j ACCEPT || true
iptables -A FORWARD -i tun+ -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT || true
iptables -A FORWARD -i eth0 -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT || true
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

# Helper to install and start the gateway client from a .ovpn file
cat > /root/install-gateway-client.sh << 'CLIENT_INSTALL_EOF'
#!/bin/bash
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <path-to-gateway-ovpn> [remote-server-cidr]" >&2
    echo "  Example: $0 /root/lanB-gw.ovpn 10.0.0.0/16" >&2
    exit 1
fi

OVPN_FILE="$1"
REMOTE_CIDR_INPUT="$${2:-$${REMOTE_CIDR:-10.0.0.0/16}}"

if [ ! -f "$OVPN_FILE" ]; then
    echo "ERROR: File not found: $OVPN_FILE" >&2
    exit 2
fi

NAME=$(basename "$OVPN_FILE" .ovpn)
NAME=$(basename "$NAME" .conf)

# Ensure route to remote site (LAN A) is included for site-to-site
NET="$${REMOTE_CIDR_INPUT%/*}"
MASK=$(python3 - "$REMOTE_CIDR_INPUT" <<'PY'
import ipaddress, sys
n = ipaddress.IPv4Network(sys.argv[1], strict=False)
print(n.netmask)
PY
)

set +e
grep -q "^route $${NET} " "$OVPN_FILE"
HAS_ROUTE=$?
set -e

if [ $HAS_ROUTE -ne 0 ]; then
    echo "Adding route $${NET} $${MASK} to client profile for site-to-site..."
    if grep -q "</ca>" "$OVPN_FILE"; then
        sed -i "/<\\/ca>/i route $${NET} $${MASK}" "$OVPN_FILE"
    elif grep -q "</cert>" "$OVPN_FILE"; then
        sed -i "/<\\/cert>/i route $${NET} $${MASK}" "$OVPN_FILE"
    else
        echo "" >> "$OVPN_FILE"
        echo "route $${NET} $${MASK}" >> "$OVPN_FILE"
    fi
fi

mkdir -p /etc/openvpn
cp -f "$OVPN_FILE" "/etc/openvpn/$${NAME}.conf"
chmod 600 "/etc/openvpn/$${NAME}.conf"

echo "Starting OpenVPN client service..."
if systemctl list-unit-files | grep -q openvpn-client@; then
    systemctl enable --now "openvpn-client@$${NAME}" || true
else
    systemctl enable --now "openvpn@$${NAME}" || true
fi

sleep 2
systemctl status "openvpn-client@$${NAME}" --no-pager || systemctl status "openvpn@$${NAME}" --no-pager || true

echo "==============================================="
echo "✓ Client installed and started: openvpn-client@$${NAME}"
echo "Check status: systemctl status openvpn-client@$${NAME}"
echo "View logs: journalctl -u openvpn-client@$${NAME} -f"
echo "==============================================="
CLIENT_INSTALL_EOF

chmod +x /root/install-gateway-client.sh

cat > /etc/motd << CLIENT_MOTD_EOF
===============================================
OpenVPN Client Gateway (LAN B)
===============================================

Setup complete. To connect to LAN A:
1. Download the gateway .ovpn file from LAN A server
2. Run: sudo /root/install-gateway-client.sh /path/to/lanB-gw.ovpn $REMOTE_CIDR

===============================================
CLIENT_MOTD_EOF

echo "✓ Client setup complete. Ready to install gateway .ovpn file."
