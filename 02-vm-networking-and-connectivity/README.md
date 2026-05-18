# VM Networking and Connectivity

This section focuses on virtualization storage management, QEMU socket networking, and Network Block Device (NBD) functionality using Alpine Linux virtual machines within a virtualized infrastructure environment.

The project explores how virtual machines communicate with each other, how virtual disks can be managed and resized, and how remote block storage can be exported and mounted across systems using QEMU networking tools.

## Topics Covered

- Virtual disk provisioning and storage management
- qcow2 and raw disk formats
- Thin provisioned virtual disks
- QEMU socket networking
- Static IP configuration
- VM to VM communication
- Network Block Device functionality
- Remote disk mounting and persistence testing

## Components Completed

### Part 1 – Virtual Disk Management

- Created 5GB qcow2 thin provisioned disk
- Created 5GB raw disk
- Compared virtual disk usage and storage allocation
- Resized qcow2 disk from 5GB to 10GB
- Converted qcow2 disk to raw format

### Part 2 – QEMU Socket Networking

- Configured two Alpine Linux virtual machines
- Assigned static IP addresses
- Tested VM to VM communication using ping and networking utilities
- Verified isolated virtual network connectivity

### Part 3 – Network Block Device

- Created a shared 1GB qcow2 virtual disk on VM1
- Exported the disk using qemu nbd
- Connected remotely from VM2 using nbd client
- Created and mounted ext4 filesystem
- Wrote test data to the mounted device
- Verified persistence and accessibility from VM1

## Technologies Used

- QEMU
- Alpine Linux
- Linux networking tools
- qemu nbd
- nbd client
- qcow2 virtual disks
- Raw disk images
- SSH and virtual networking

