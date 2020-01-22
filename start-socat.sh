#!/bin/bash

set -o errexit

set -x

DIRNAME=$(dirname $(readlink -f $0))
ID=$1

IP="10.11.$(echo $ID | awk -e '{ printf("%d.%d", $0 / 253, $0 % 253 + 2); }')"
sudo ip netns exec "sim$1" socat - TCP-LISTEN:1883,fork,reuseaddr,bind=$IP > /dev/null
