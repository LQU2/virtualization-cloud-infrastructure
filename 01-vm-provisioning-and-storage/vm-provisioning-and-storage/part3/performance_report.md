# Performance Comparison Report

## Test Environment
- Host OS: Windows
- Guest OS: Alpine Linux 3.21
- CPU: 2 vCPUs
- Memory: 1 GB RAM
- Disk: 10GB qcow2
- Virtualization: QEMU (pure emulation)

## Hardware Acceleration
Hardware acceleration (WHPX) was attempted but could not be initialized due to host hypervisor constraints. As a result, all benchmarks were conducted using emulation. Expected performance improvements with acceleration are discussed conceptually.

## CPU Performance
The CPU benchmark showed significantly slower execution compared to typical hardware-accelerated virtualization. Emulated execution introduces noticeable overhead, making CPU-bound workloads less efficient.

## Boot Time
The VM reached the login prompt in approximately XX.X seconds under emulation, which is slower than expected for accelerated environments.

## Disk I/O
Disk throughput was measured using `dd`. Performance was functional but slower than native disk speeds, consistent with emulated I/O behavior.

## Practical Usability
Pure emulation is usable for testing, learning, and lightweight workloads, but not ideal for performance-sensitive applications.

## Recommendation
Hardware acceleration should be used whenever available. Emulation remains a viable fallback when acceleration is unavailable.
