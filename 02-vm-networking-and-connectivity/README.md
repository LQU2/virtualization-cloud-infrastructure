This explores virtual disk formats, QEMU socket networking, and Network Block Device (NBD) functionality. Two Alpine Linux virtual machines were configured and connected using QEMU socket networking. A virtual disk was exported from VM1 and mounted remotely on VM2 using NBD.



\---



\## Components Completed



\### Part 1 – Virtual Disk Management

\- Created 5GB qcow2 (thin provisioned) disk

\- Created 5GB raw disk

\- Compared disk usage

\- Resized qcow2 disk to 10GB

\- Converted qcow2 to raw format



\### Part 2 – QEMU Socket Networking

\- Created two Alpine VMs

\- Configured static IP addresses

\- Verified VM-to-VM connectivity via ping



\### Part 3 – Network Block Device

\- Created 1GB shared qcow2 disk on VM1

\- Exported disk using qemu-nbd

\- Connected from VM2 using nbd-client

\- Created ext4 filesystem

\- Wrote test file

\- Verified persistence on VM1



