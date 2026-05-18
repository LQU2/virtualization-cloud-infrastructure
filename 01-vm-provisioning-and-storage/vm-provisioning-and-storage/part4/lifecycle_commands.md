
VM Lifecycle Operations

Internal Snapshot:
savevm before_changes
loadvm before_changes

External Snapshot:
qemu-img create -f qcow2 -b base.qcow2 overlay.qcow2

Full Clone:
qemu-img convert -f qcow2 -O qcow2 base.qcow2 fullclone.qcow2

Linked Clone:
qemu-img create -f qcow2 -b base.qcow2 linked.qcow2

Dual VM Ports:
VM1 SSH: 2222
VM2 SSH: 2223
