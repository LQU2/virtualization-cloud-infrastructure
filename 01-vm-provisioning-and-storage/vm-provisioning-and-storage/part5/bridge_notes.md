ip link add br0 type bridge
ip addr add 192.168.100.1/24 dev br0
ip link set br0 up
ip tuntap add tap0 mode tap
ip link set tap0 master br0
ip link set tap0 up

The VM would then be started with -netdev tap to attach it to the bridge.
