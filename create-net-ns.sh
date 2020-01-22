#!/bin/bash

# Create networks interfaces and network namespace to run processes in an
# isolated network stack.

# Two interfaces are created. One with a fake generated MAC address for
# communication on the network and one with veth (virtual ethernet) for the
# communication between the processes running in the network namespace and the
# host (named peer below).

# Technically it would be possible to use the veth pair to communicate with the
# network but it would work only with NAT and we want to have multiple MAC
# addresses to simulate the assets. That's why we use also macvlan and not
# only veth.

set -x

set -e

function gen_mac_last_octets() {
    echo $1 | awk -e ' { hex = sprintf("%04x", $0); split(hex, arr, ""); printf("%s%s:%s%s", arr[1], arr[2], arr[3], arr[4]) }'
}

if [ $(id -u) -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

if [ -z "$1" ];  then
    echo "Missing serial parameter"
    exit 1
fi

ID=$1

HWLINK=eth0
MACVLN=macvlan$ID
MACVHWADDR="02:00:00:00:$(gen_mac_last_octets $ID)"
TESTHOST=www.google.com
NETNS=sim$ID
NEWNAME=eth0

# while ! ping -q -c 1 $TESTHOST > /dev/null
# do
# 	echo "$0: Cannot ping $TESTHOST, waiting another 5 secs..."
# 	sleep 5
# done

# deleting the namespace is not enough to free the assigned IP, so we delete it before
ip netns exec $NETNS ip link delete $HWLINK &> /dev/null || true
# force deletion of the old namespace
ip net del $NETNS &> /dev/null || true

# ------------
# get network config
# ------------

IP=$(ip address show dev $HWLINK | grep "inet " | awk '{print $2}')
NETWORK=$(ip -4 route list exact default | head -n1 | cut -d' ' -f3)
GATEWAY=$(ip -o route | grep default | awk '{print $3}')

# ------------
# setting up $MACVLN interface
# ------------


# force deletion of old interface
ip link delete $MACVLN &> /dev/null || true
ip link add link $HWLINK $MACVLN address $MACVHWADDR type macvlan mode bridge

ip netns add $NETNS
ip link set dev $MACVLN netns $NETNS name $NEWNAME

# the net ns still has the same ip as the host for the macvlan interface
ip netns exec $NETNS ip address add $IP dev $NEWNAME
ip netns exec $NETNS ip link set $NEWNAME up
ip netns exec $NETNS ip route add $NETWORK dev $NEWNAME
ip netns exec $NETNS ip route add default via $GATEWAY

# lo
ip netns exec $NETNS ip link set lo up

## add bridge interface between host and namespace
VETH="veth1-$NETNS"
VPEER="vpeer1-$NETNS"
VETH_ADDR="10.11.1.1"

VPEER_ADDR="10.11.$(echo $ID | awk -e '{ printf("%d.%d", $0 / 253, $0 % 253 + 2); }')"

# Create veth link.
ip link delete $VETH &> /dev/null || true
ip link add ${VETH} type veth peer name ${VPEER}

# Add peer-1 to NS.
ip link set ${VPEER} netns $NETNS

ip addr add ${VETH_ADDR}/16 dev ${VETH}
ip link set ${VETH} up

# Setup IP ${VPEER}.
ip netns exec $NETNS ip addr add ${VPEER_ADDR}/16 dev ${VPEER}
ip netns exec $NETNS ip link set ${VPEER} up

# Add specific route for the IP
ip route del $VPEER_ADDR dev $VETH &> /dev/null || true
ip route add $VPEER_ADDR dev $VETH

# Test connectivity from namespace to peer (host)
ip netns exec $NETNS ping -W 20 -q -c 1 ${VETH_ADDR} &> /dev/null

if [ $? -ne 0 ]; then
    echo "Cannot ping ${VETH_ADDR} from the network namespace. Check your firewall rules."
    echo "sim$ID: Cannot ping ${VETH_ADDR} from the network namespace. Check your firewall rules." >> /tmp/netns.log
    ip netns exec $NETNS ip addr
    exit 1
fi

echo $VPEER_ADDR
