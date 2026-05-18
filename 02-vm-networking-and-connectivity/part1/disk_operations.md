\# Part 1 – Virtual Disk Management



\## Creating Disk Images



\### Create 5GB qcow2 (Thin Provisioned)



qemu-img create -f qcow2 disk\_qcow2\_5g.qcow2 5G





\### Create 5GB raw disk



qemu-img create -f raw disk\_raw\_5g.img 5G





\## Disk Usage Comparison



Thin provisioning allows qcow2 images to only consume space as data is written, while raw images allocate full space immediately.



Commands used:



ls -lh

du -h disk\_qcow2\_5g.qcow2

du -h disk\_raw\_5g.img





Result:

\- qcow2 initially consumed only a few MB.

\- raw consumed full 5GB.



\## Resizing Disk





qemu-img resize disk\_qcow2\_5g.qcow2 10G

qemu-img info disk\_qcow2\_5g.qcow2





Virtual size increased to 10GB without consuming additional physical space.



\## Disk Conversion





qemu-img convert -f qcow2 -O raw disk\_qcow2\_5g.qcow2 converted\_raw.img





Converted disk successfully from qcow2 to raw format.

