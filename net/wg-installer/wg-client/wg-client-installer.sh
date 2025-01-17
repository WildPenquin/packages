#!/bin/sh

. /usr/share/wginstaller/rpcd_ubus.sh
. /usr/share/wginstaller/wg.sh

CMD=$1
shift

while true; do
	case "$1" in
	-h | --help)
		echo "help"
		shift 1
		;;
	-i | --ip)
		IP=$2
		shift 2
		;;
	--user)
		USER=$2
		shift 2
		;;
	--password)
		PASSWORD=$2
		shift 2
		;;
	--bandwidth)
		BANDWIDTH=$2
		shift 2
		;;
	--mtu)
		WG_MTU=$2
		shift 2
		;;
	--wg-key-file)
		WG_KEY_FILE=$2
		shift 2
		;;
	'')
		break
		;;
	*)
		break
		;;
	esac
done

escape_ip () {
	local gw_ip=$1

	# ipv4 processing
	ret_ip=$(echo $gw_ip | tr '.' '_')

	# ipv6 processing
	ret_ip=$(echo $ret_ip | tr ':' '_')
	ret_ip=$(echo $ret_ip | cut -d '[' -f 2)
	ret_ip=$(echo $ret_ip | cut -d ']' -f 1)

	echo $ret_ip
}

register_client_interface () {
	local privkey=$1
	local pubkey=$2
	local gw_ip=$3
	local gw_port=$4
	local endpoint=$5
	local mtu_client=$6

	port_start=$(uci get wgclient.@client[0].port_start)
	port_end=$(uci get wgclient.@client[0].port_end)
	base_prefix=$(uci get wgclient.@client[0].base_prefix)

	port=$(next_port $port_start $port_end)
	ifname="wg_$port"

	offset=$(($port - $port_start))
	client_ip=$(owipcalc $base_prefix add $offset next 128)
	client_ip_assign="${client_ip}/128"

	echo "Installing Interface With:"
	echo "Endpoint ${endpoint}"
	echo "Client IP ${client_ip}"
	echo "Port ${port}"
	echo "Pubkey ${pubkey}"

	ip link add dev $ifname type wireguard

	ip -6 addr add dev $ifname $client_ip
	ip -6 addr add dev $ifname fe80::2/64
	wg set $ifname listen-port $port private-key $privkey peer $pubkey allowed-ips 0.0.0.0/0,::0/0 endpoint "${endpoint}:${gw_port}"
	ip link set up dev $ifname
	ip link set mtu $mtu_client dev $ifname # configure mtu here!
}

# rpc login
token="$(request_token $IP $USER $PASSWORD)"
if [ $? != 0 ]; then
	echo "failed to register token"
	exit 1
fi

# now call procedure
case $CMD in
"get_usage")
	wg_rpcd_get_usage $token $IP
	;;
"register")

	if [ ! -z "$WG_KEY_FILE" ]; then
		wg_priv_key_file=$WG_KEY_FILE
		wg_pub_key=$(wg pubkey < $WG_KEY_FILE)
	else
		wg_priv_key_file=$(uci get wgclient.@client[0].wg_key)
		wg_pub_key=$(cat $(uci get wgclient.@client[0].wg_pub))
	fi

	register_output=$(wg_rpcd_register $token $IP $BANDWIDTH $WG_MTU $wg_pub_key)
	if [ $? != 0 ]; then
		echo "Failed to Register!"
		exit 1
	fi
	pubkey=$(echo $register_output | awk '{print $2}')
	ip_addr=$(echo $register_output | awk '{print $4}')
	port=$(echo $register_output | awk '{print $6}')
	client_ip=$(echo $register_output | awk '{print $8}')
	register_client_interface $wg_priv_key_file $pubkey $ip_addr $port $IP $WG_MTU
	;;
*) echo "Usage: wg-client-installer [cmd] --ip [2001::1] --user wginstaller --password wginstaller" ;;
esac
