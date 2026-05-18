\# Part 2 – QEMU Socket Networking



\## VM1 (Listener)





qemu-system-x86\_64

-m 1024

-drive file=vm1.qcow2,format=qcow2

-netdev socket,id=net0,listen=:1234

-device virtio-net-pci,netdev=net0





\## VM2 (Connector)





qemu-system-x86\_64

-m 1024

-drive file=vm2.qcow2,format=qcow2

-netdev socket,id=net0,connect=localhost:1234

-device virtio-net-pci,netdev=net0





\## Static IP Configuration



VM1:



ip addr add 192.168.100.10/24 dev eth0

ip link set eth0 up





VM2:



ip addr add 192.168.100.11/24 dev eth0

ip link set eth0 up





\## Connectivity Verification





ping 192.168.100.11

ping 192.168.100.10





Ping successful in both directions.



\## Explanation



QEMU socket networking creates a direct Layer 2 link between VMs without requiring root privileges. This allows VMs to communicate directly without external networking infrastructure.

