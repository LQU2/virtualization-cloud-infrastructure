# CIS 395 Lab Environment

This repository contains the lab environment provisioning system for UFV CIS 395: Virtualization and Cloud Infrastructure (Winter 2026).

## Overview

The lab environment uses QEMU to run an Alpine Linux virtual machine with **turnkey setup** - no manual installation required. The VM auto-configures on first boot using cloud-init.

**Pre-installed software:**
- **Container stack:** docker, containerd, k3s (Kubernetes)
- **Development tools:** gcc, make, gdb, strace
- **System utilities:** lscpu, dmidecode, qemu-img
- **Editors and shells:** vim, nano, tmux, bash

## Prerequisites

### Windows (MSYS2 UCRT64)

1. Install MSYS2 from https://www.msys2.org/
2. Open "MSYS2 UCRT64" terminal
3. Install required packages:
   ```bash
   pacman -S mingw-w64-ucrt-x86_64-qemu xorriso git curl
   ```

### macOS

1. Install Homebrew from https://brew.sh/
2. Install required packages:
   ```bash
   brew install qemu git cdrtools
   ```
   Note: curl is already included with macOS

### Linux

Use your distribution's package manager:

| Distribution | Command |
|--------------|---------|
| Debian/Ubuntu | `sudo apt install qemu-system-x86 qemu-utils git curl genisoimage` |
| Fedora | `sudo dnf install qemu-system-x86 qemu-img git curl genisoimage` |
| Arch | `sudo pacman -S qemu-full git curl cdrtools` |
| openSUSE | `sudo zypper install qemu-x86 qemu-tools git curl genisoimage` |

## Quick Start

### 1. Clone this repository

```bash
git clone https://sc-gitlab.ufv.ca/202601cis395on1/lab-environment.git
cd lab-environment
```

### 2. Initialize the environment

```bash
./provision.sh init
```

This will:
- Download the pre-installed Alpine Linux cloud image
- Create a cloud-init configuration for auto-setup
- Prepare the VM disk

### 3. Start the VM

```bash
# Without hardware acceleration (works everywhere):
./provision.sh start cis395-vm

# With hardware acceleration (faster):
# Linux:
./provision.sh start cis395-vm -enable-kvm
# macOS:
./provision.sh start cis395-vm -accel hvf
# Windows (if available):
./provision.sh start cis395-vm -accel whpx
```

**Duplicate instance protection:** If a QEMU instance is already running with the same VM image (even from a different directory), you'll be warned and given options:
- `[t]` **Terminate** - kill the existing instance and start fresh
- `[c]` **Cancel** - abort (recommended if you're unsure)

This prevents accidentally running multiple instances of the same VM, which could corrupt the disk image.

On first boot, cloud-init will automatically:
- Create the student user account
- Install development tools, Docker, containerd, k3s
- Configure SSH access
- Set up the welcome message

**First boot takes 2-3 minutes** for auto-configuration. Subsequent boots are faster.

### 4. Connect via SSH

In a new terminal:

```bash
./provision.sh ssh
```

Or manually:

```bash
ssh -p 2222 student@localhost
```

**Smart connection handling:**

- If the VM isn't running, you'll be prompted to start it automatically
- If the VM is still booting (no login prompt in `vm.log` yet), you'll see options:
  - `[r]` **Retry** - wait and check every 30 seconds until ready
  - `[y]` **Yes** - try to connect anyway
  - `[n]` **No** - cancel and exit

- After exiting your SSH session, you'll see a reminder to stop the VM if you're done working

## SSH Connection Options

Once you have the VM running, there are several ways to connect via SSH. Choose the approach that fits your workflow.

| Your Situation | Recommended Approach | Notes |
|----------------|---------------------|-------|
| First time connecting | `./provision.sh ssh` | Handles host keys automatically; password: student/student |
| Want to connect from any directory | `ssh -p 2222 student@localhost` | Will see host key warning on first connect and after VM reset |
| Using VS Code Remote SSH | SSH config alias (see below) | Enables seamless VS Code integration |
| Want passwordless login | Set up authorized_keys | See `./provision.sh setup-ssh` for guided setup |
| Windows with multiple SSH clients | See platform notes below | Native SSH vs MSYS2 vs Git Bash have different config locations |

### Why Host Key Warnings Occur

When you connect with `ssh -p 2222 student@localhost`, you may see a warning about the host key. This happens because the VM generates new SSH keys when it is reset or recreated. The `./provision.sh ssh` command handles this automatically by not storing host keys persistently.

### SSH Config for VS Code Remote SSH

To use VS Code's Remote SSH extension with the VM, add this to your SSH config file:

```
Host cis395vm
    HostName localhost
    Port 2222
    User student
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
```

**SSH config file locations by platform:**

| Platform | Config File Location |
|----------|---------------------|
| Linux/macOS | `~/.ssh/config` |
| Windows (native SSH) | `%USERPROFILE%\.ssh\config` |
| MSYS2/Git Bash | `~/.ssh/config` (within that environment) |

After adding this config, you can connect with `ssh cis395vm` or select "cis395vm" in VS Code's Remote SSH extension.

### Setting Up Passwordless Login

If you prefer key-based authentication instead of typing the password each time, run:

```bash
./provision.sh setup-ssh
```

This guides you through copying your public key to the VM's authorized_keys file.

**Default credentials:**
- Username: `student`
- Password: `student`

**Root access:**
- The `student` user has full sudo privileges without a password
- To run commands as root: `sudo <command>`
- To get a root shell: `sudo -i`

**Change your password after first login!**

## Verifying Your Environment

After SSH into the VM, run:

```bash
./verify-environment.sh
```

This checks:
- CPU virtualization features
- Docker and containerd status
- Git configuration
- Required utilities

## Hardware Acceleration

Hardware acceleration makes your VM run 10-20x faster. The provisioning script accepts QEMU acceleration arguments:

**Linux (KVM):**
```bash
./provision.sh start cis395-vm -enable-kvm
# Check if KVM is available:
ls -l /dev/kvm
```

**macOS (HVF):**
```bash
./provision.sh start cis395-vm -accel hvf
# M1/M2 Macs:
./provision.sh start cis395-vm -accel hvf -cpu host
```

**Windows (WHPX):**
```bash
# Requires Hyper-V Platform feature enabled
./provision.sh start cis395-vm -accel whpx
```

**If acceleration is not available:**
- VM will use TCG emulation mode (slower but works everywhere)
- This is fine for learning; all features work, just slower
- Week 2 activity explores the performance difference

## Commands

| Command | Description |
|---------|-------------|
| `./provision.sh init` | Download image and create cloud-init config |
| `./provision.sh start [image] [qemu-args]` | Start the VM with optional QEMU arguments |
| `./provision.sh ssh` | Connect to VM via SSH |
| `./provision.sh session N` | Run session-specific setup script |
| `./provision.sh status` | Show VM and disk status |
| `./provision.sh stop [--force]` | Stop the running VM |
| `./provision.sh reset` | Delete VM disk and start fresh |
| `./provision.sh build [gitpush]` | Build and optionally push to GitLab |
| `./provision.sh help` | Show detailed help |

## Troubleshooting

### VM won't start

1. Check dependencies: `./provision.sh init` will verify required tools
2. Check logs: `tail -f vm.log` (in another terminal while VM is starting)
3. Try without acceleration: `./provision.sh start cis395-vm`
4. If you see "QEMU instance already running" warning, another VM with the same image is running:
   - Choose `[t]` to terminate it and start fresh
   - Choose `[c]` to cancel and connect to the existing VM instead
5. If still stuck: `./provision.sh reset` and start over

### SSH connection refused

1. Wait longer - first boot takes 2-3 minutes for package installation
2. Use `./provision.sh ssh` which has smart retry handling:
   - If VM isn't running, it offers to start it
   - If VM is booting, choose `[r]` to retry every 30 seconds until ready
3. Check if VM is running: `./provision.sh status`
4. Monitor boot progress: `tail -f vm.log`
5. Manual connection: `ssh -p 2222 student@localhost`

### Can't connect to internet from inside VM

The VM uses QEMU's user-mode networking (SLIRP), which should work automatically. If you have issues:

1. Test connectivity: `ping -c 3 1.1.1.1` (inside VM)
2. Test DNS: `nslookup google.com` (inside VM)
3. Check QEMU networking is working: `curl http://example.com`

### Docker commands fail

1. Check docker service: `sudo service docker status`
2. Verify user is in docker group: `groups` (should show "docker")
3. Restart docker: `sudo service docker restart`
4. If still failing, try with sudo: `sudo docker run hello-world`
5. Log out and back in for group changes to take effect

### VM is very slow

1. Use hardware acceleration if available (see Hardware Acceleration section above)
2. Without KVM/HVF/WHPX, VM runs in TCG emulation mode (10-20x slower)
3. This is expected on cloud VMs or systems without virtualization support
4. All features still work, just slower

### Lost VM or can't stop it

1. Check status: `./provision.sh status`
2. Graceful stop: `./provision.sh stop`
3. Force stop: `./provision.sh stop --force`
4. Emergency cleanup: `./provision.sh stop-all` (kills all QEMU instances)

### Want to start fresh

```bash
./provision.sh stop
./provision.sh reset
./provision.sh init
./provision.sh start cis395-vm [accel-args]
```

## Support

If you encounter issues:
1. Check the troubleshooting section above
2. Try `./provision.sh reset` to start fresh
3. Ask in the course discussion forum
4. Attend office hours for in-person help

## About This Environment

This environment uses Alpine Linux's [NoCloud cloud-init images](https://alpinelinux.org/cloud/). The provisioning script downloads a pre-installed system image that auto-configures on first boot based on cloud-init configuration.

Why Alpine Linux?
- Lightweight (< 500MB with full container stack installed)
- Fast boot times
- Excellent for learning containers and cloud technologies
- Same base used by many Docker containers in production
- Full package ecosystem via apk package manager

## Session-Specific Setup

Some course sessions may require additional setup. Use the session command to run session-specific configuration:

```bash
./provision.sh session 2   # Run Session 2 setup
```

## Advanced Usage

### Multiple VMs

You can create multiple VMs by specifying different image names:

```bash
# Create additional VMs
./provision.sh start cis395-vm2 -enable-kvm
./provision.sh start cis395-vm3 -enable-kvm
```

Note: Only one VM can run at a time with this script. Stop the current one first.

### Accessing VM Console

The VM runs in headless mode. To see console output:

```bash
tail -f vm.log
```

### Custom VM Configuration

Edit the configuration variables at the top of `provision.sh`:

- `VM_MEMORY` - Default: 2G (increase for k3s workloads)
- `VM_DISK_SIZE` - Default: 8G
- `SSH_PORT` - Default: 2222
- `VM_USER` - Default: student

### Nested Virtualization

To enable nested virtualization (running VMs inside the VM), you need:

1. Host supports nested virt (check `/sys/module/kvm_*/parameters/nested`)
2. Pass nested flag to QEMU: `./provision.sh start cis395-vm -enable-kvm -cpu host`
3. Inside VM, load kvm module: `sudo modprobe kvm-intel` or `sudo modprobe kvm-amd`

This is optional and only needed for advanced assignments.
