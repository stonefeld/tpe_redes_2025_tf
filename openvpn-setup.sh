#!/bin/bash

# OpenVPN Server Preparation Script for Ubuntu 24.04
# This script prepares the system and creates setup scripts for manual VPN configuration

set -e

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install OpenVPN and Easy-RSA
echo "Installing OpenVPN and Easy-RSA..."
apt-get install -y openvpn easy-rsa

# Create directory for Easy-RSA
mkdir -p /etc/openvpn/easy-rsa
cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/

# Enable IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# Configure iptables for NAT (basic rules)
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE
iptables -A INPUT -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -j ACCEPT
iptables -A FORWARD -i tun+ -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o tun+ -m state --state RELATED,ESTABLISHED -j ACCEPT

# Make iptables rules persistent
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent

# Save current iptables rules (including NAT)
iptables-save > /etc/iptables/rules.v4

# Verify NAT rule is saved
echo "Verifying NAT rule is saved..."
iptables -t nat -L -n -v | grep MASQUERADE

# Create OpenVPN server configuration template
cat > /etc/openvpn/server.conf << 'EOF'
port 1194
proto udp
dev tun

# Certificate paths (will be updated after certificate generation)
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem

# TLS authentication for HMAC verification
tls-auth /etc/openvpn/ta.key 0

# Additional security settings for HMAC
auth SHA256
cipher AES-256-GCM

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

keepalive 10 120
user nobody
group nogroup
persist-key
persist-tun

status openvpn-status.log
verb 3
explicit-exit-notify 1
EOF

# Create VPN setup script for manual execution (with password options)
cat > /root/setup-vpn.sh << 'EOF'
#!/bin/bash

# OpenVPN Server Setup Script (Manual Intervention)
# Run this script to complete the VPN server setup with security options

set -e

echo "==============================================="
echo "OpenVPN Server Setup (Manual)"
echo "==============================================="

cd /etc/openvpn/easy-rsa

echo "Step 1: Initializing PKI..."
./easyrsa init-pki

echo "Step 2: Creating Certificate Authority..."
echo "You will be prompted to enter a passphrase for the CA key."
echo "You can press Enter to use no passphrase (not recommended for production)."
./easyrsa build-ca

echo "Step 3: Generating server certificate..."
echo "You will be prompted to enter a passphrase for the server key."
echo "You can press Enter to use no passphrase (not recommended for production)."
./easyrsa build-server-full server

echo "Step 4: Generating Diffie-Hellman parameters..."
echo "This may take a few minutes..."
./easyrsa gen-dh

echo "Step 5: Generating TLS auth key..."
openvpn --genkey --secret /etc/openvpn/ta.key

echo "Step 6: Setting proper permissions..."
chmod 600 /etc/openvpn/ta.key
chmod 600 /etc/openvpn/easy-rsa/pki/private/*.key
chmod 644 /etc/openvpn/easy-rsa/pki/issued/*.crt
chmod 644 /etc/openvpn/easy-rsa/pki/ca.crt
chmod 644 /etc/openvpn/easy-rsa/pki/dh.pem

echo "Step 7: Starting OpenVPN service..."
systemctl start openvpn@server
systemctl enable openvpn@server

echo "Step 8: Checking service status..."
systemctl status openvpn@server --no-pager

echo "==============================================="
echo "OpenVPN server setup completed!"
echo "Server IP: $(curl -s ipinfo.io/ip)"
echo "Port: 1194"
echo "Protocol: UDP"
echo "==============================================="
EOF

chmod +x /root/setup-vpn.sh

# Create client configuration script (with password options)
cat > /root/client-setup.sh << 'EOF'
#!/bin/bash

# Script to generate client certificates and configurations (Manual)

if [ $# -eq 0 ]; then
    echo "Usage: $0 <client-name>"
    exit 1
fi

CLIENT_NAME=$1
cd /etc/openvpn/easy-rsa

echo "Generating client certificate for: $CLIENT_NAME"
echo "You will be prompted to enter a passphrase for the client key."
echo "You can press Enter to use no passphrase (not recommended for production)."
./easyrsa build-client-full $CLIENT_NAME

# Get the public IP address
PUBLIC_IP=$(curl ipinfo.io/ip)

# Create client configuration
cat > /root/$CLIENT_NAME.ovpn << CLIENT_EOF
client
dev tun
proto udp
remote $PUBLIC_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun

# Security settings matching server
auth SHA256
cipher AES-256-GCM

# TLS authentication for HMAC verification (CRITICAL)
tls-auth ta.key 1

verb 3

<ca>
$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/easy-rsa/pki/issued/$CLIENT_NAME.crt)
</cert>

<key>
$(cat /etc/openvpn/easy-rsa/pki/private/$CLIENT_NAME.key)
</key>

<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>
CLIENT_EOF

echo "Client configuration created: /root/$CLIENT_NAME.ovpn"
echo "Download this file to your client and import it into your OpenVPN client."

# If the IP wasn't detected, provide instructions
if [ "$PUBLIC_IP" = "YOUR_SERVER_IP" ]; then
    echo ""
    echo "IMPORTANT: The public IP could not be detected automatically."
    echo "Please get the IP and then edit /root/$CLIENT_NAME.ovpn replacing 'YOUR_SERVER_IP'"
    echo ""
fi
EOF

chmod +x /root/client-setup.sh

# Create passwordless client setup script
cat > /root/client-setup-auto.sh << 'CLIENT_AUTO_EOF'
#!/bin/bash

# Automated client setup script (passwordless)

if [ $# -eq 0 ]; then
    echo "Usage: $0 <client-name>"
    exit 1
fi

CLIENT_NAME=$1
cd /etc/openvpn/easy-rsa

# Source the vars file
source /etc/openvpn/easy-rsa/vars

echo "Generating client certificate for: $CLIENT_NAME (automated, no passphrase)"
# Build client certificate without passphrase
./easyrsa --batch build-client-full $CLIENT_NAME nopass

# Get the public IP address
PUBLIC_IP=$(curl -s ipinfo.io/ip)

# Create client configuration
cat > /root/$CLIENT_NAME.ovpn << CLIENT_CONFIG_EOF
client
dev tun
proto udp
remote $PUBLIC_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun

# Security settings matching server
auth SHA256
cipher AES-256-GCM

# TLS authentication for HMAC verification (CRITICAL)
tls-auth ta.key 1

verb 3

<ca>
$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/easy-rsa/pki/issued/$CLIENT_NAME.crt)
</cert>

<key>
$(cat /etc/openvpn/easy-rsa/pki/private/$CLIENT_NAME.key)
</key>

<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>
CLIENT_CONFIG_EOF

echo "Client configuration created: /root/$CLIENT_NAME.ovpn"
echo "Download this file to your client and import it into your OpenVPN client."

# Set proper permissions
chmod 600 /root/$CLIENT_NAME.ovpn
chmod 600 /etc/openvpn/easy-rsa/pki/private/$CLIENT_NAME.key

echo "✓ Client setup completed automatically (no passphrases)"
CLIENT_AUTO_EOF

chmod +x /root/client-setup-auto.sh

# Create management script
cat > /root/vpn-management.sh << 'EOF'
#!/bin/bash

# OpenVPN Management Script

case "$1" in
    status)
        systemctl status openvpn@server
        ;;
    start)
        systemctl start openvpn@server
        ;;
    stop)
        systemctl stop openvpn@server
        ;;
    restart)
        systemctl restart openvpn@server
        ;;
    logs)
        journalctl -u openvpn@server -f
        ;;
    clients)
        echo "Connected clients:"
        if [ -f "/var/log/openvpn/openvpn-status.log" ]; then
            cat /var/log/openvpn/openvpn-status.log | grep "CLIENT_LIST"
        else
            echo "No status log found. OpenVPN may not be running."
        fi
        ;;
    *)
        echo "Usage: $0 {status|start|stop|restart|logs|clients}"
        exit 1
        ;;
esac
EOF

chmod +x /root/vpn-management.sh

# Create a welcome message
cat > /etc/motd << 'EOF'
===============================================
OpenVPN Server Setup Complete
===============================================

System has been automatically configured with:
✓ OpenVPN and Easy-RSA installed
✓ IP forwarding enabled
✓ Firewall rules configured
✓ Certificates generated (passwordless)
✓ OpenVPN service running

AUTOMATED SETUP (Ready to use):
- Server is already running and ready for clients
- Use: sudo /root/client-setup-auto.sh <client-name>

MANUAL INTERVENTION (If needed):
- For password-protected setup: sudo /root/setup-vpn.sh
- For manual client creation: sudo /root/client-setup.sh <client-name>

MANAGEMENT:
- Service control: sudo /root/vpn-management.sh {status|start|stop|restart|logs|clients}

Server IP: $(curl ipinfo.io/ip)
Port: 1194
Protocol: UDP

===============================================
EOF

# Automated OpenVPN setup (passwordless for user data)
echo "Starting automated OpenVPN setup..."
cd /etc/openvpn/easy-rsa

# Initialize PKI
./easyrsa init-pki

# Create vars file for passwordless operation
cat > /etc/openvpn/easy-rsa/vars << 'VARS_EOF'
# Easy-RSA configuration for automated deployment
export KEY_COUNTRY="US"
export KEY_PROVINCE="CA"
export KEY_CITY="SanFrancisco"
export KEY_ORG="MyOrg"
export KEY_EMAIL="admin@example.com"
export KEY_OU="MyOrgUnit"
export KEY_NAME="server"
export KEY_ALTNAMES="server"
VARS_EOF

# Source the vars file
source /etc/openvpn/easy-rsa/vars

# Build CA without passphrase (automated)
echo "Building CA without passphrase (automated)..."
./easyrsa --batch build-ca nopass

# Build server certificate without passphrase (automated)
echo "Building server certificate without passphrase (automated)..."
./easyrsa --batch build-server-full server nopass

# Generate DH parameters
echo "Generating Diffie-Hellman parameters..."
./easyrsa gen-dh

# Generate TLS auth key
echo "Generating TLS auth key..."
openvpn --genkey --secret /etc/openvpn/ta.key

# Set proper permissions
chmod 600 /etc/openvpn/ta.key
chmod 600 /etc/openvpn/easy-rsa/pki/private/*.key
chmod 644 /etc/openvpn/easy-rsa/pki/issued/*.crt
chmod 644 /etc/openvpn/easy-rsa/pki/ca.crt
chmod 644 /etc/openvpn/easy-rsa/pki/dh.pem

# Start OpenVPN service
echo "Starting OpenVPN service..."
systemctl start openvpn@server
systemctl enable openvpn@server

# Log completion
echo "OpenVPN server setup completed automatically at $(date)" >> /var/log/openvpn-prep.log
echo "Server IP: $(curl -s ipinfo.io/ip)" >> /var/log/openvpn-prep.log
echo "Use /root/client-setup-auto.sh <client-name> for automated client creation" >> /var/log/openvpn-prep.log
echo "Use /root/setup-vpn.sh for manual setup with password options" >> /var/log/openvpn-prep.log
