#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Community Add-on: WireGuard
# Creates the interface configuration
# ==============================================================================
declare -a list
declare addresses
declare allowed_ips
declare config
declare config_dir
declare dns
declare endpoint
declare filename
declare fwmark
declare host
declare interface
declare keep_alive
declare mtu
declare name
declare peer_private_key
declare peer_public_key
declare port
declare post_down
declare post_up
declare pre_down
declare pre_shared_key
declare pre_up
declare server_private_key
declare server_public_key
declare table

if ! bashio::fs.directory_exists '/ssl/wireguard'; then
    mkdir -p /ssl/wireguard ||
        bashio::exit.nok "Could not create wireguard storage folder!"
fi

# Get interface and config file location
interface="wg0"
if bashio::config.has_value "server.interface"; then
    interface=$(bashio::config "server.interface")
fi
config="/etc/wireguard/${interface}.conf"

# Start creation of configuration
echo "[Interface]" > "${config}"

# Check if at least 1 address is specified
if ! bashio::config.has_value 'server.addresses'; then
    bashio::exit.nok 'You need at least 1 address configured for the server'
fi

# Add all server addresses to the configuration
for address in $(bashio::config 'server.addresses'); do
    [[ "${address}" == *"/"* ]] || address="${address}/24"
    echo "Address = ${address}" >> "${config}"
done

# Add all server DNS addresses to the configuration
if bashio::config.has_value 'server.dns'; then
    for dns in $(bashio::config 'server.dns'); do
        echo "DNS = ${dns}" >> "${config}"
    done
else
    dns=$(bashio::dns.host)
    echo "DNS = ${dns}" >> "${config}"
fi

# Get the server's private key
if bashio::config.has_value 'server.private_key'; then
    server_private_key=$(bashio::config 'server.private_key')
fi

# Get the server pubic key
if bashio::config.has_value 'server.public_key'; then
    server_public_key=$(bashio::config 'server.public_key')
else

fwmark=$(bashio::config "server.fwmark")
mtu=$(bashio::config "server.mtu")
pre_down=$(bashio::config "server.pre_down")
pre_up=$(bashio::config "server.pre_up")
table=$(bashio::config "server.table")

# Pre Up & Down handling
if [[ "${pre_up}" = "off" ]]; then
    pre_up=""
fi
if [[ "${pre_down}" = "off" ]]; then
    pre_down=""
fi

# Post Up & Down defaults
post_up="iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE"
post_down="iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE"
if [[ $(</proc/sys/net/ipv4/ip_forward) -eq 0 ]]; then
    bashio::log.warning
    bashio::log.warning "IP forwarding is disabled on the host system!"
    bashio::log.warning "You can still use WireGuard to access Hass.io,"
    bashio::log.warning "however, you cannot access your home network or"
    bashio::log.warning "the internet via the VPN tunnel."
    bashio::log.warning
    bashio::log.warning "Please consult the add-on documentation on how"
    bashio::log.warning "to resolve this."
    bashio::log.warning

    # Set fake placeholders for Up & Down commands
    post_up=""
    post_down=""
fi

# Load custom PostUp setting if provided
if bashio::config.has_value 'server.post_up'; then
    post_up=$(bashio::config 'server.post_up')
    if [[ "${post_up}" = "off" ]]; then
        post_up=""
    fi
fi

# Load custom PostDown setting if provided
if bashio::config.has_value 'server.post_down'; then
    post_down=$(bashio::config 'server.post_down')
    if [[ "${post_down}" = "off" ]]; then
        post_down=""
    fi
fi

# Finish up the main server configuration
{
    echo "PrivateKey = ${server_private_key}"

    # Adds server port to the configuration
    echo "ListenPort = 51820"

    # Custom routing table
    bashio::config.has_value "server.table" && echo "Table = ${table}"

    # Pre up & down
    bashio::config.has_value "server.pre_up" && echo "PreUp = ${pre_up}"
    bashio::config.has_value "server.pre_down" && echo "PreDown = ${pre_down}"

    # Post up & down
    bashio::var.has_value "${post_up}" && echo "PostUp = ${post_up}"
    bashio::var.has_value "${post_down}" && echo "PostDown = ${post_down}"

    # fwmark for outgoing packages
    bashio::config.has_value "server.fwmark" && echo "FwMark = ${fwmark}"

    # Custom MTU setting
    bashio::config.has_value "server.mtu" && echo "MTU = ${mtu}"

    # End configuration file with an empty line
    echo ""
} >> "${config}"

# Finish up the main server configuration
{
    echo "[Peer]" > "${config}"
    echo "PublicKey = ${server_public_key}"
    echo "PresharedKey = ${pre_shared_key}"
    echo "Endpoint = ${endpoint}"
    echo "AllowedIPs = ${allowed_ips}"
    echo ""
} >> "${config}"


# Get DNS for client configurations
if bashio::config.has_value 'server.dns'; then
    dns=$(bashio::config "server.dns | join(\", \")")
fi
