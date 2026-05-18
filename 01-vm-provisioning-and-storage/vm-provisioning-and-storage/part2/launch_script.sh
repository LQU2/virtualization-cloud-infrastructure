#!/bin/bash

qemu-system-x86_64 \
-drive file=images/alpine10g.qcow2,format=qcow2 \
-nic user,hostfwd=tcp::2222-:22 \
-m 1024 \
-smp 2 \
-nographic
