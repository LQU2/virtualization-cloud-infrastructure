\# Part 3 – Network Block Device (NBD)



\## VM1 – NBD Server



Create shared disk:



qemu-img create -f qcow2 share.qcow2 1G





Export disk:



qemu-nbd --bind=192.168.100.10 -x myshare share.qcow2





---



\## VM2 – NBD Client



Load module:



modprobe nbd max\_part=8





Connect:



nbd-client 192.168.100.10 10809 /dev/nbd0 -N myshare





Create filesystem:



mkfs.ext4 /dev/nbd0





Mount and write file:



mkdir /mnt/nbd

mount /dev/nbd0 /mnt/nbd

echo "CIS395 SUCCESS" > /mnt/nbd/testfile.txt





---



\## Persistence Verification



After disconnecting client:



On VM1:



qemu-nbd -c /dev/nbd0 share.qcow2

mount /dev/nbd0 /mnt/check

ls /mnt/check





File `testfile.txt` was present, confirming data persistence.

