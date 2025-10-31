#!/bin/bash

# OpenVPN Server Setup (LAN A)

set -e

# Values injected via user data template
LOCAL_CIDR="${local_cidr}"
REMOTE_CIDR="${remote_cidr}"
PEER_CN="${peer_gateway_common_name}"

echo "==============================================="
echo "OpenVPN Server Setup"
echo "Local CIDR: $LOCAL_CIDR"
echo "Remote CIDR: $REMOTE_CIDR"
echo "Peer CN: $PEER_CN"
echo "==============================================="

echo "Updating system packages..."
apt-get update
apt-get upgrade -y

echo "Installing OpenVPN server dependencies..."
apt-get install -y openvpn easy-rsa nginx apache2-utils python3 iptables-persistent || true

# Enable IP forwarding and basic NAT for VPN pool
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p || true
iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE || true
iptables -A INPUT -i tun+ -j ACCEPT || true
iptables-save > /etc/iptables/rules.v4 2>/dev/null || true

# Prepare download directory for exporting client configs
mkdir -p /var/www/ovpn-export
chown root:www-data /var/www/ovpn-export
chmod 750 /var/www/ovpn-export

# Configure Nginx site for protected downloads
cat > /etc/nginx/sites-available/ovpn << 'EOF'
server {
    listen 80;
    server_name _;

    # Redirect root to /download/
    location = / { return 302 /download/; }

    # Protected download path: /download/<username>/<file>.ovpn
    location ~ ^/download/([^/]+)/(.+\.ovpn)$ {
        alias /var/www/ovpn-export/$1/$2;
        auth_basic "Ovpn Download";
        auth_basic_user_file /etc/nginx/.ovpn_htpasswd;
        autoindex off;
        limit_except GET HEAD { deny all; }
        access_log /var/log/nginx/ovpn_downloads.log;
    }
}
EOF

ln -sf /etc/nginx/sites-available/ovpn /etc/nginx/sites-enabled/ovpn
[ -f /etc/nginx/sites-enabled/default ] && rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx || true

# Easy-RSA base dir
mkdir -p /etc/openvpn/easy-rsa
cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/

# OpenVPN server configuration
cat > /etc/openvpn/server.conf << 'EOF'
port 1194
proto udp
dev tun

# Certificates
ca /etc/openvpn/easy-rsa/pki/ca.crt
cert /etc/openvpn/easy-rsa/pki/issued/server.crt
key /etc/openvpn/easy-rsa/pki/private/server.key
dh /etc/openvpn/easy-rsa/pki/dh.pem

# TLS authentication
tls-auth /etc/openvpn/ta.key 0
auth SHA256
cipher AES-256-GCM

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt

# Site-to-site essentials
topology subnet
client-config-dir /etc/openvpn/ccd

keepalive 10 120
user nobody
group nogroup
persist-key
persist-tun

status openvpn-status.log
verb 3
explicit-exit-notify 1
EOF

mkdir -p /etc/openvpn/ccd
chmod 755 /etc/openvpn/ccd

# Helper: add route to server.conf if not present
add_server_route() {
  local cidr="$1"
  local net="$${cidr%/*}"
  local mask=$(python3 - "$cidr" <<'PY'
import ipaddress, sys
n = ipaddress.IPv4Network(sys.argv[1], strict=False)
print(n.netmask)
PY
)
  grep -q "^route $net $mask$" /etc/openvpn/server.conf || echo "route $net $mask" >> /etc/openvpn/server.conf
}

echo "Starting automated OpenVPN server setup..."
cd /etc/openvpn/easy-rsa

./easyrsa init-pki

cat > /etc/openvpn/easy-rsa/vars << 'VARS_EOF'
export KEY_COUNTRY="US"
export KEY_PROVINCE="CA"
export KEY_CITY="SanFrancisco"
export KEY_ORG="MyOrg"
export KEY_EMAIL="admin@example.com"
export KEY_OU="MyOrgUnit"
export KEY_NAME="server"
export KEY_ALTNAMES="server"
VARS_EOF

source /etc/openvpn/easy-rsa/vars

./easyrsa --batch build-ca nopass
./easyrsa --batch build-server-full server nopass
./easyrsa gen-dh
openvpn --genkey --secret /etc/openvpn/ta.key

chmod 600 /etc/openvpn/ta.key
chmod 600 /etc/openvpn/easy-rsa/pki/private/*.key
chmod 644 /etc/openvpn/easy-rsa/pki/issued/*.crt
chmod 644 /etc/openvpn/easy-rsa/pki/ca.crt
chmod 644 /etc/openvpn/easy-rsa/pki/dh.pem

# Configure site-to-site: add route and CCD
add_server_route "$REMOTE_CIDR"

REM_NET="$${REMOTE_CIDR%/*}"
REM_MASK=$(python3 - "$REMOTE_CIDR" <<'PY'
import ipaddress, sys
n = ipaddress.IPv4Network(sys.argv[1], strict=False)
print(n.netmask)
PY
)
echo "iroute $${REM_NET} $REM_MASK" > "/etc/openvpn/ccd/$PEER_CN"
chmod 644 "/etc/openvpn/ccd/$PEER_CN"

# Export utility (make available before any export usage)
cat > /root/ovpn-export << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ $# -ne 2 ]; then
  echo "Usage: $0 <client-name> <username>" >&2
  exit 1
fi
CLIENT="$1"
USER_NAME="$2"
SRC="/root/$CLIENT.ovpn"
DEST_DIR="/var/www/ovpn-export/$USER_NAME"
DEST="$DEST_DIR/$CLIENT.ovpn"
if [ ! -f "$SRC" ]; then
  echo "ERROR: $SRC no existe" >&2
  exit 2
fi
mkdir -p "$DEST_DIR"
chown root:www-data "$DEST_DIR"
chmod 750 "$DEST_DIR"
cp -f "$SRC" "$DEST"
chown root:www-data "$DEST"
chmod 640 "$DEST"
PUBLIC_IP=$(curl -s ipinfo.io/ip || echo "<IP_O_DOMINIO>")
echo "Archivo exportado: /download/$USER_NAME/$CLIENT.ovpn"
echo "URL: http://$PUBLIC_IP/download/$USER_NAME/$CLIENT.ovpn"
EOF

chmod +x /root/ovpn-export

# Create peer gateway client cert and export
./easyrsa --batch build-client-full "$PEER_CN" nopass
PUBLIC_IP=$(curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")

cat > /root/$PEER_CN.ovpn << CLIENT_CONFIG_EOF
client
dev tun
proto udp
remote $PUBLIC_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun

auth SHA256
cipher AES-256-GCM
tls-auth ta.key 1
verb 3

# Route LAN A (server-side VPC) over the tunnel for site-to-site
route $${LOCAL_CIDR%/*} $(python3 - "$LOCAL_CIDR" <<'PY'
import ipaddress, sys
n = ipaddress.IPv4Network(sys.argv[1], strict=False)
print(n.netmask)
PY
)

<ca>
$(cat /etc/openvpn/easy-rsa/pki/ca.crt)
</ca>

<cert>
$(cat /etc/openvpn/easy-rsa/pki/issued/$PEER_CN.crt)
</cert>

<key>
$(cat /etc/openvpn/easy-rsa/pki/private/$PEER_CN.key)
</key>

<tls-auth>
$(cat /etc/openvpn/ta.key)
</tls-auth>
CLIENT_CONFIG_EOF

chmod 600 /root/$PEER_CN.ovpn

PASSWORD=$(openssl rand -base64 12)
if [ ! -f /etc/nginx/.ovpn_htpasswd ]; then
    htpasswd -b -c /etc/nginx/.ovpn_htpasswd "$PEER_CN" "$PASSWORD"
else
    htpasswd -b /etc/nginx/.ovpn_htpasswd "$PEER_CN" "$PASSWORD"
fi

/root/ovpn-export "$PEER_CN" "$PEER_CN"

# Create client-setup-auto.sh for regular client-to-site users
cat > /root/client-setup-auto.sh << 'CLIENT_AUTO_EOF'
#!/bin/bash
set -e
if [ $# -eq 0 ]; then
    echo "Usage: $0 <client-name>"
    exit 1
fi
CLIENT_NAME=$1
cd /etc/openvpn/easy-rsa
source /etc/openvpn/easy-rsa/vars
./easyrsa --batch build-client-full $CLIENT_NAME nopass
PUBLIC_IP=$(curl -s ipinfo.io/ip)
cat > /root/$CLIENT_NAME.ovpn << CLIENT_CONFIG_EOF
client
dev tun
proto udp
remote $PUBLIC_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
auth SHA256
cipher AES-256-GCM
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
chmod 600 /root/$CLIENT_NAME.ovpn
PASSWORD=$(openssl rand -base64 12)
if [ ! -f /etc/nginx/.ovpn_htpasswd ]; then
    htpasswd -b -c /etc/nginx/.ovpn_htpasswd "$CLIENT_NAME" "$PASSWORD"
else
    htpasswd -b /etc/nginx/.ovpn_htpasswd "$CLIENT_NAME" "$PASSWORD"
fi
/root/ovpn-export "$CLIENT_NAME" "$CLIENT_NAME"
echo "==============================================="
echo "Usuario: $CLIENT_NAME"
echo "Password: $PASSWORD"
echo "Link: http://$PUBLIC_IP/download/$CLIENT_NAME/$CLIENT_NAME.ovpn"
echo "==============================================="
CLIENT_AUTO_EOF

chmod +x /root/client-setup-auto.sh

# Management script
cat > /root/vpn-management.sh << 'EOF'
#!/bin/bash
case "$1" in
    status) systemctl status openvpn@server ;;
    start) systemctl start openvpn@server ;;
    stop) systemctl stop openvpn@server ;;
    restart) systemctl restart openvpn@server ;;
    logs) journalctl -u openvpn@server -f ;;
    clients)
        echo "Connected clients:"
        if [ -f "/var/log/openvpn/openvpn-status.log" ]; then
            cat /var/log/openvpn/openvpn-status.log | grep "CLIENT_LIST"
        else
            echo "No status log found. OpenVPN may not be running."
        fi
        ;;
    *) echo "Usage: $0 {status|start|stop|restart|logs|clients}"; exit 1 ;;
esac
EOF

chmod +x /root/vpn-management.sh

echo "Starting OpenVPN service..."
systemctl start openvpn@server
systemctl enable openvpn@server

PUBLIC_IP=$(curl -s ipinfo.io/ip || echo "YOUR_SERVER_IP")
cat > /etc/motd << SERVER_MOTD_EOF
===============================================
OpenVPN Server Setup Complete (LAN A)
===============================================
✓ Server running
✓ Site-to-site configured for $PEER_CN → $REMOTE_CIDR
✓ Gateway certificate exported: http://$PUBLIC_IP/download/$PEER_CN/$PEER_CN.ovpn

Client-to-site:
- Use: sudo /root/client-setup-auto.sh <client-name>
SERVER_MOTD_EOF

echo "✓ OpenVPN server setup complete."


