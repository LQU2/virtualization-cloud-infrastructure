#!/bin/bash
# implementation_schema=docs/implementation_schema/lab-environment.schema.md
# CIS 395 Lab Environment Provisioner
# =====================================
# Supports: Windows (MSYS2), macOS, Linux
#
# Uses Alpine Linux NoCloud cloud-init images for turnkey setup.
# No manual installation required - VM auto-configures on first boot.
#
# Usage:
#   ./provision.sh init     # Download image and create cloud-init config
#   ./provision.sh start    # Start the VM (auto-configures on first boot)
#   ./provision.sh ssh      # Connect to the VM via SSH
#   ./provision.sh stop     # Stop the running VM
#   ./provision.sh status   # Show VM status
#   ./provision.sh help     # Show detailed help

set -e
set +x  # Clean output (set -x for debugging)

# =============================================================================
# COURSE CONFIGURATION
# =============================================================================

COURSE_CODE="cis395"
COURSE_NAME="CIS 395"
VERSION="2026.01"

VM_NAME="${COURSE_CODE}-vm"
VM_HOSTNAME="${COURSE_CODE}-lab"

# =============================================================================
# VM CONFIGURATION
# =============================================================================

ALPINE_VERSION="3.21"
ALPINE_IMAGE="nocloud_alpine-${ALPINE_VERSION}.0-x86_64-bios-cloudinit-r0.qcow2"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/cloud/${ALPINE_IMAGE}"

VM_MEMORY="2G"
VM_CPUS="2"
VM_DISK_SIZE="8G"
SSH_PORT="2222"
MONITOR_PORT="4444"
VM_USER="student"

TIMEOUT_FIRST_BOOT=300
TIMEOUT_SUBSEQUENT=120

LOCKFILE=".vm.lock"
PIDFILE=".vm.pid"
LOGFILE="vm.log"

# =============================================================================
# PLATFORM DETECTION
# =============================================================================

detect_platform() {
    case "$(uname -s)" in
        MINGW*|MSYS*)
            PLATFORM="windows"
            QEMU_IMG="/ucrt64/bin/qemu-img"
            QEMU_SYSTEM="/ucrt64/bin/qemu-system-x86_64"
            ;;
        Darwin)
            PLATFORM="macos"
            QEMU_IMG="qemu-img"
            QEMU_SYSTEM="qemu-system-x86_64"
            ;;
        Linux)
            PLATFORM="linux"
            QEMU_IMG="qemu-img"
            QEMU_SYSTEM="qemu-system-x86_64"
            ;;
        *)
            echo "[ERROR] Unsupported platform: $(uname -s)"
            exit 1
            ;;
    esac
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

process_exists() {
    local pid=$1
    case "$PLATFORM" in
        windows)
            # MSYS2: try kill -0 first (works for MSYS2-spawned processes),
            # fall back to checking ps output for Windows processes
            kill -0 "$pid" 2>/dev/null || ps -W 2>/dev/null | grep -q "^[ ]*$pid " 2>/dev/null
            ;;
        *) kill -0 "$pid" 2>/dev/null ;;
    esac
}

kill_process() {
    local pid=$1
    local sig=${2:-TERM}

    case "$PLATFORM" in
        windows)
            if [[ "$sig" == "9" || "$sig" == "KILL" ]] && command -v taskkill &>/dev/null; then
                taskkill //F //PID "$pid" 2>/dev/null || kill -9 "$pid" 2>/dev/null
            else
                kill -"$sig" "$pid" 2>/dev/null
            fi
            ;;
        *)
            kill -"$sig" "$pid" 2>/dev/null
            ;;
    esac
}

# =============================================================================
# VM STATE MANAGEMENT
# =============================================================================

is_vm_running() {
    if [[ -f "$LOCKFILE" ]]; then
        local pid=$(cat "$PIDFILE" 2>/dev/null)

        if [[ -n "$pid" ]] && process_exists "$pid"; then
            return 0
        fi

        rm -f "$LOCKFILE" "$PIDFILE"
    fi
    return 1
}

get_vm_info() {
    if [[ -f "$LOCKFILE" ]]; then
        cat "$LOCKFILE"
    else
        echo "No VM running"
    fi
}

stop_vm() {
    local force="${1:-false}"

    if ! is_vm_running; then
        echo "[INFO] No VM is currently running"
        return 0
    fi

    local pid=$(cat "$PIDFILE" 2>/dev/null)

    if [[ -z "$pid" ]]; then
        echo "[WARN] Lockfile exists but no PID found"
        rm -f "$LOCKFILE" "$PIDFILE"
        return 1
    fi

    echo "[INFO] Found running VM (PID: $pid)"

    if [[ "$force" == "true" ]]; then
        echo "[INFO] Force stopping VM..."
        kill_process "$pid" 9
        echo "[OK] VM force stopped"
    else
        echo "[INFO] Gracefully stopping VM..."
        kill_process "$pid" TERM

        local i
        for i in {1..10}; do
            process_exists "$pid" || break
            sleep 1
        done

        if process_exists "$pid"; then
            echo "[WARN] Graceful shutdown timed out, force stopping..."
            kill_process "$pid" 9
        fi
        echo "[OK] VM stopped"
    fi

    rm -f "$LOCKFILE" "$PIDFILE"
}

stop_all_vms() {
    echo "[INFO] Searching for all QEMU instances..."

    local pids
    case "$PLATFORM" in
        windows)
            # Try ps -W for Windows processes, fall back to ps aux
            pids=$(ps -W 2>/dev/null | grep -i 'qemu' | awk '{print $1}')
            [[ -z "$pids" ]] && pids=$(ps aux 2>/dev/null | grep '[q]emu-system-x86_64' | awk '{print $1}')
            ;;
        *)
            pids=$(pgrep -f 'qemu-system-x86_64' 2>/dev/null)
            ;;
    esac

    if [[ -n "$pids" ]]; then
        echo "[INFO] Found QEMU processes: $pids"
        echo "$pids" | xargs -r kill -9 2>/dev/null
        echo "[OK] Stopped all QEMU instances"
    else
        echo "[INFO] No QEMU instances found"
    fi

    rm -f "$LOCKFILE" "$PIDFILE"
}

# Check for existing QEMU instances running the same image (cross-platform)
# Returns 0 if user chose to terminate or no conflicts, 1 if user cancelled
check_existing_qemu() {
    local our_image
    our_image=$(realpath "images/${VM_NAME}.qcow2" 2>/dev/null || echo "images/${VM_NAME}.qcow2")

    local qemu_procs=""
    local conflicting_pids=""

    # Get list of running QEMU processes with their command lines
    case "$PLATFORM" in
        windows)
            # Windows/MSYS2: use ps aux to get process info
            qemu_procs=$(ps aux 2>/dev/null | grep 'qemu-system-x86_64' | grep -v grep || true)
            ;;
        macos)
            # macOS: use ps with full command line (-ww prevents truncation)
            qemu_procs=$(ps -ww -eo pid,command 2>/dev/null | grep 'qemu-system-x86_64' | grep -v grep || true)
            ;;
        linux)
            # Linux: use ps with full command line
            qemu_procs=$(ps -eo pid,args 2>/dev/null | grep 'qemu-system-x86_64' | grep -v grep || true)
            ;;
    esac

    if [[ -z "$qemu_procs" ]]; then
        return 0  # No QEMU processes running
    fi

    # Check each QEMU process for image match
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local pid
        local cmdline

        case "$PLATFORM" in
            windows)
                pid=$(echo "$line" | awk '{print $1}')
                cmdline="$line"
                ;;
            *)
                pid=$(echo "$line" | awk '{print $1}')
                cmdline=$(echo "$line" | cut -d' ' -f2-)
                ;;
        esac

        # Skip if this is our own known PID from this directory
        if [[ -f "$PIDFILE" ]]; then
            local our_pid
            our_pid=$(cat "$PIDFILE" 2>/dev/null)
            if [[ "$pid" == "$our_pid" ]]; then
                continue
            fi
        fi

        # Extract image paths from command line and check for match
        local found_match=false

        # Look for -drive file=... pattern
        if echo "$cmdline" | grep -qE "(^|[[:space:]])images/${VM_NAME}\.qcow2([[:space:]]|$|,)"; then
            found_match=true
        fi

        # Also check for absolute path match
        if echo "$cmdline" | grep -qF "$our_image"; then
            found_match=true
        fi

        # Check for image filename anywhere in command (covers various arg formats)
        if echo "$cmdline" | grep -qF "${VM_NAME}.qcow2"; then
            found_match=true
        fi

        if $found_match; then
            conflicting_pids="$conflicting_pids $pid"
        fi
    done <<< "$qemu_procs"

    # Trim whitespace
    conflicting_pids=$(echo "$conflicting_pids" | xargs)

    if [[ -z "$conflicting_pids" ]]; then
        return 0  # No conflicting processes
    fi

    # Found conflicting process(es)
    echo "=========================================="
    echo "  WARNING: QEMU instance already running"
    echo "=========================================="
    echo ""
    echo "Found existing QEMU process(es) that appear to be running"
    echo "the same image (${VM_NAME}.qcow2):"
    echo ""
    echo "  PID(s): $conflicting_pids"
    echo ""
    echo "Running multiple instances with the same disk image can"
    echo "cause data corruption."
    echo ""
    echo "Options:"
    echo "  [t] Terminate - kill the existing instance(s) and start fresh"
    echo "  [c] Cancel    - abort starting (recommended if unsure)"
    echo ""

    while true; do
        read -p "Choose an option (t/C): " -n 1 -r
        echo
        case "$REPLY" in
            [Tt])
                echo "[INFO] Terminating existing QEMU instance(s)..."
                for pid in $conflicting_pids; do
                    echo "[INFO] Stopping PID $pid..."
                    kill_process "$pid" TERM

                    # Wait briefly for graceful shutdown
                    local i
                    for i in {1..5}; do
                        process_exists "$pid" || break
                        sleep 1
                    done

                    # Force kill if still running
                    if process_exists "$pid"; then
                        echo "[WARN] Force stopping PID $pid..."
                        kill_process "$pid" 9
                    fi
                done
                echo "[OK] Existing instance(s) terminated"
                echo ""
                # Clean up any stale lockfiles in other directories
                # (we can only clean our own, but at least inform user)
                return 0
                ;;
            [Cc]|"")
                echo "Cancelled. Existing VM continues running."
                echo ""
                echo "[TIP] To connect to the existing VM, find its directory and run:"
                echo "      ./provision.sh ssh"
                return 1
                ;;
            *)
                echo "Invalid option. Please enter t or c."
                ;;
        esac
    done
}

# =============================================================================
# DEPENDENCY CHECKING
# =============================================================================

check_dependencies() {
    local missing=""

    command -v "$QEMU_SYSTEM" &>/dev/null || missing="$missing qemu"
    command -v "$QEMU_IMG" &>/dev/null || missing="$missing qemu-img"
    command -v curl &>/dev/null || missing="$missing curl"
    command -v nc &>/dev/null || missing="$missing netcat"

    if ! command -v genisoimage &>/dev/null && \
       ! command -v mkisofs &>/dev/null && \
       ! command -v xorriso &>/dev/null; then
        missing="$missing iso-tools"
    fi

    if [[ -n "$missing" ]]; then
        echo "[ERROR] Missing required tools:$missing"
        echo ""
        case "$PLATFORM" in
            windows)
                echo "Install with:"
                echo "  pacman -S mingw-w64-ucrt-x86_64-qemu xorriso curl openbsd-netcat"
                ;;
            macos)
                echo "Install with:"
                echo "  brew install qemu cdrtools netcat"
                ;;
            linux)
                echo "Install using your distribution's package manager:"
                echo ""
                echo "  Debian/Ubuntu:"
                echo "    sudo apt install qemu-system-x86 qemu-utils genisoimage curl netcat-openbsd"
                echo ""
                echo "  Fedora:"
                echo "    sudo dnf install qemu-system-x86 qemu-img genisoimage curl netcat"
                echo ""
                echo "  Arch:"
                echo "    sudo pacman -S qemu-full cdrtools curl openbsd-netcat"
                ;;
        esac
        echo ""
        echo "After installing, run './provision.sh init' again."
        exit 1
    fi
}

# =============================================================================
# IMAGE AND DISK MANAGEMENT
# =============================================================================

download_alpine() {
    if [[ ! -f "images/$ALPINE_IMAGE" ]]; then
        echo "[INFO] Downloading Alpine Linux $ALPINE_VERSION NoCloud image..."
        curl -L --progress-bar -o "images/$ALPINE_IMAGE" "$ALPINE_URL"
        echo "[OK] Downloaded Alpine NoCloud image"
    else
        echo "[OK] Alpine NoCloud image already present"
    fi
}

create_disk() {
    if [[ ! -f "images/${VM_NAME}.qcow2" ]]; then
        echo "[INFO] Creating VM disk from base image..."
        cp "images/$ALPINE_IMAGE" "images/${VM_NAME}.qcow2"
        $QEMU_IMG resize "images/${VM_NAME}.qcow2" "$VM_DISK_SIZE"
        echo "[OK] Created VM disk: images/${VM_NAME}.qcow2"
    else
        echo "[OK] VM disk already exists"
    fi
}

# =============================================================================
# CLOUD-INIT CONFIGURATION
# =============================================================================

create_cloudinit_iso() {
    echo "[INFO] Creating cloud-init ISO..."

    # Verify user-data exists (should be checked into git)
    if [[ ! -f "cloudinit/user-data" ]]; then
        echo "[ERROR] cloudinit/user-data not found"
        echo "        This file should exist in the repository."
        exit 1
    fi

    # Create meta-data (simple instance identification)
    cat > cloudinit/meta-data << EOF
instance-id: ${VM_HOSTNAME}
local-hostname: ${VM_HOSTNAME}
EOF

    # Create ISO from existing user-data and generated meta-data
    if command -v genisoimage &>/dev/null; then
        genisoimage -output cloudinit/cidata.iso -volid cidata -joliet -rock \
            cloudinit/user-data cloudinit/meta-data 2>/dev/null
    elif command -v mkisofs &>/dev/null; then
        mkisofs -output cloudinit/cidata.iso -volid cidata -joliet -rock \
            cloudinit/user-data cloudinit/meta-data 2>/dev/null
    else
        xorriso -as genisoimage -output cloudinit/cidata.iso -volid cidata -joliet -rock \
            cloudinit/user-data cloudinit/meta-data 2>/dev/null
    fi

    echo "[OK] Created cloud-init ISO"
}

# =============================================================================
# VM START (Background Mode)
# =============================================================================

start_vm() {
    local extra_args=("$@")
    local first_boot=false

    # Check if already running (from this directory)
    if is_vm_running; then
        echo "[ERROR] A VM is already running!"
        echo ""
        get_vm_info
        echo ""
        echo "Options:"
        echo "  - Connect to it: ./provision.sh ssh"
        echo "  - Stop it first: ./provision.sh stop"
        echo "  - Force stop:    ./provision.sh stop --force"
        exit 1
    fi

    # Check for QEMU instances running the same image (from any directory)
    if ! check_existing_qemu; then
        exit 1
    fi

    if [[ ! -f "images/${VM_NAME}.qcow2" ]]; then
        echo "[ERROR] VM disk not found: images/${VM_NAME}.qcow2"
        echo "Run './provision.sh init' first to set up the VM"
        exit 1
    fi

    # Always regenerate cidata.iso to pick up bootcmd updates
    # bootcmd runs on every boot, so updates take effect immediately
    if [[ -f "cloudinit/user-data" ]]; then
        create_cloudinit_iso
    fi

    # Detect first boot (no .first-boot-done marker in VM disk state)
    local cloudinit_args=""
    if [[ -f "cloudinit/cidata.iso" ]]; then
        cloudinit_args="-cdrom cloudinit/cidata.iso"
        # Check if this is truly first boot by looking for our local marker
        if [[ ! -f ".first-boot-done" ]]; then
            first_boot=true
        fi
    fi

    local max_wait=$TIMEOUT_SUBSEQUENT
    if $first_boot; then
        max_wait=$TIMEOUT_FIRST_BOOT
        echo "[INFO] First boot - VM will auto-configure via cloud-init..."
        echo "[INFO] This may take several minutes. Please wait."
    fi

    echo "[INFO] Starting VM: ${VM_NAME}"
    echo "[INFO] SSH will be available on localhost:${SSH_PORT}"
    echo "[INFO] QEMU monitor on localhost:${MONITOR_PORT}"
    echo "[INFO] Username: ${VM_USER} | Password: student"
    echo "[INFO] Log file: ${LOGFILE}"
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        echo "[INFO] Extra QEMU args: ${extra_args[*]}"
    fi
    echo ""

    cat > "$LOCKFILE" << EOF
VM Name: ${VM_NAME}
Started: $(date)
SSH Port: ${SSH_PORT}
Monitor Port: ${MONITOR_PORT}
Platform: ${PLATFORM}
Log File: ${LOGFILE}
EOF

    $QEMU_SYSTEM \
        -m "$VM_MEMORY" \
        -smp "$VM_CPUS" \
        -drive file="images/${VM_NAME}.qcow2",format=qcow2 \
        $cloudinit_args \
        -netdev user,id=net0,hostfwd=tcp::${SSH_PORT}-:22 \
        -device virtio-net-pci,netdev=net0 \
        -nographic \
        -serial file:"${LOGFILE}" \
        -monitor tcp:127.0.0.1:${MONITOR_PORT},server,nowait \
        "${extra_args[@]}" &

    local qemu_pid=$!
    echo "$qemu_pid" > "$PIDFILE"

    sleep 1
    if ! process_exists $qemu_pid; then
        echo "[ERROR] Failed to start QEMU"
        rm -f "$LOCKFILE" "$PIDFILE"
        exit 1
    fi

    echo "[OK] VM started (PID: $qemu_pid)"
    echo "[INFO] Waiting for SSH..."

    local ssh_wait=0
    local ssh_ready=false

    while [[ $ssh_wait -lt $max_wait ]]; do
        if ! process_exists $qemu_pid; then
            echo ""
            echo "[ERROR] VM process exited unexpectedly"
            echo "[INFO] Check ${LOGFILE} for details"
            rm -f "$LOCKFILE" "$PIDFILE"
            exit 1
        fi

        if nc -z localhost "$SSH_PORT" 2>/dev/null; then
            ssh_ready=true
            break
        fi

        sleep 2
        ssh_wait=$((ssh_wait + 2))
        echo -n "."
    done
    echo ""

    if $ssh_ready; then
        echo "[OK] SSH is available!"
        # Mark first boot as done so subsequent starts don't show first-boot messages
        if $first_boot; then
            touch ".first-boot-done"
        fi
    else
        echo "[WARN] SSH not responding yet. VM may still be booting."
        echo "[INFO] Monitor with: tail -f ${LOGFILE}"
    fi

    echo ""
    echo "[INFO] VM is running in background (PID: $qemu_pid)"
    echo ""
    if $first_boot; then
        echo "=========================================="
        echo "  IMPORTANT: First-time provisioning"
        echo "=========================================="
        echo ""
        echo "The VM is installing packages and configuring"
        echo "itself via cloud-init. This takes 3-5 minutes."
        echo ""
        echo "Wait for provisioning to complete before connecting."
        echo "You can monitor progress with:"
        echo "  tail -f ${LOGFILE}"
        echo ""
        echo "Look for '${VM_HOSTNAME} login:' prompt in the log,"
        echo "then press Ctrl+C (Cmd+C on Mac) to exit the log viewer."
        echo ""
        echo "Login as '${VM_USER}' (not root). Password: student"
        echo ""
    fi
    echo "[INFO] Connect: ./provision.sh ssh"
    echo "[INFO] Stop:    ./provision.sh stop"
    echo "[INFO] Monitor: tail -f ${LOGFILE} (Ctrl+C to exit)"
}

# =============================================================================
# SSH CONNECTION
# =============================================================================

# Check if VM boot is ready (login prompt visible in log)
check_boot_ready() {
    if [[ -f "$LOGFILE" ]]; then
        # Look for login prompt or cloud-init completion as boot indicators
        if grep -q "login:" "$LOGFILE" 2>/dev/null || \
           grep -q "Cloud-init.*finished" "$LOGFILE" 2>/dev/null || \
           grep -q "reached target.*Cloud-init" "$LOGFILE" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Wait for boot with periodic retry
wait_for_boot() {
    local interval=${1:-30}
    echo "[INFO] Waiting for VM to finish booting..."
    echo "[INFO] Checking ${LOGFILE} for 'login:' prompt every ${interval} seconds"
    echo "[INFO] Press Ctrl+C to cancel"
    echo ""

    while true; do
        if check_boot_ready; then
            echo ""
            echo "[OK] VM boot complete - login prompt detected!"
            return 0
        fi

        # Check VM is still running
        if ! is_vm_running; then
            echo ""
            echo "[ERROR] VM is no longer running"
            return 1
        fi

        echo -n "."
        sleep "$interval"
    done
}

connect_ssh() {
    # Check if VM is running
    if ! is_vm_running; then
        echo "[INFO] VM is not currently running."
        echo ""
        read -p "Would you like to start the VM? (Y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Nn]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
        # Start the VM
        start_vm
        echo ""
    fi

    # Check if VM appears to have finished booting
    if ! check_boot_ready; then
        echo "=========================================="
        echo "  WARNING: VM may not be ready yet"
        echo "=========================================="
        echo ""
        echo "The VM log does not show a login prompt yet."
        echo "Cloud-init provisioning may still be running."
        echo ""
        echo "Options:"
        echo "  [r] Retry - wait and check every 30 seconds for login prompt"
        echo "  [y] Yes   - try to connect anyway"
        echo "  [n] No    - cancel and exit"
        echo ""
        while true; do
            read -p "Choose an option (r/y/N): " -n 1 -r
            echo
            case "$REPLY" in
                [Rr])
                    if wait_for_boot 30; then
                        break
                    else
                        exit 1
                    fi
                    ;;
                [Yy])
                    echo "[INFO] Attempting connection anyway..."
                    break
                    ;;
                [Nn]|"")
                    echo "Cancelled. Try again after boot completes."
                    echo "[TIP] Monitor boot progress with: tail -f ${LOGFILE}"
                    exit 0
                    ;;
                *)
                    echo "Invalid option. Please enter r, y, or n."
                    ;;
            esac
        done
    fi

    echo "[INFO] Connecting to VM via SSH..."
    echo "[INFO] Default password: student"
    echo ""
    echo "[TIP] SSH agent forwarding is enabled (-A flag)."
    echo "      To use your existing SSH keys inside the VM,"
    echo "      make sure ssh-agent is running on your host:"
    echo "        eval \$(ssh-agent) && ssh-add"
    echo ""

    # Run SSH and capture exit status
    local ssh_exit=0
    ssh -A -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${VM_USER}@localhost" || ssh_exit=$?

    echo ""
    echo "Exited ssh session."
    echo ""
    echo "[TIP] If you are done working on the VM, remember to stop it:"
    echo "      ./provision.sh stop"
    echo ""

    return $ssh_exit
}

# =============================================================================
# QEMU MONITOR ACCESS
# =============================================================================
# SECURITY NOTE: The QEMU monitor uses an unauthenticated TCP connection on
# localhost. This is acceptable for local development/learning environments
# but should NEVER be exposed to external networks. The monitor provides full
# control over the VM including the ability to read/write guest memory.

monitor_vm() {
    if ! is_vm_running; then
        echo "[ERROR] VM is not running"
        echo "        Start it first with: ./provision.sh start"
        exit 1
    fi

    if ! nc -z localhost "$MONITOR_PORT" 2>/dev/null; then
        echo "[ERROR] QEMU monitor not available on port $MONITOR_PORT"
        exit 1
    fi

    echo "=========================================="
    echo "  QEMU Monitor - ${VM_NAME}"
    echo "=========================================="
    echo ""
    echo "Useful commands:"
    echo "  info status     - Show VM running state"
    echo "  info snapshots  - List internal snapshots"
    echo "  savevm <name>   - Create internal snapshot"
    echo "  loadvm <name>   - Restore internal snapshot"
    echo "  system_powerdown - Send ACPI shutdown to guest"
    echo "  quit            - Exit monitor (disconnect only)"
    echo ""
    echo "Type 'help' for full command list."
    echo "Press Ctrl+C or type 'quit' to exit."
    echo ""

    # Connect to monitor
    nc localhost "$MONITOR_PORT"
}

# =============================================================================
# SSH CONFIG SETUP
# =============================================================================

setup_ssh_config() {
    echo "=== SSH Setup for ${COURSE_NAME} Lab VM ==="
    echo ""

    # Check if VM is running
    if ! is_vm_running; then
        echo "[WARN] The VM does not appear to be running."
        echo "       Start it first with: ./provision.sh start"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi

    # Determine SSH config location based on platform
    local ssh_config_file
    local ssh_config_dir
    case "$PLATFORM" in
        windows)
            # MSYS2 uses Unix-style paths
            ssh_config_dir="$HOME/.ssh"
            ssh_config_file="$ssh_config_dir/config"
            echo "Platform: Windows (MSYS2)"
            echo ""
            echo "Note: Windows has multiple SSH config locations:"
            echo "  - MSYS2/Git Bash: ~/.ssh/config"
            echo "  - Native Windows SSH: %USERPROFILE%\\.ssh\\config"
            echo ""
            echo "This script configures the MSYS2 location."
            echo "For VS Code Remote SSH, you may need to configure both."
            ;;
        macos)
            ssh_config_dir="$HOME/.ssh"
            ssh_config_file="$ssh_config_dir/config"
            echo "Platform: macOS"
            ;;
        linux)
            ssh_config_dir="$HOME/.ssh"
            ssh_config_file="$ssh_config_dir/config"
            echo "Platform: Linux"
            ;;
    esac
    echo "SSH config file: $ssh_config_file"
    echo ""

    # Part 1: SSH Config for VS Code Remote SSH
    echo "----------------------------------------"
    echo "Part 1: SSH Config (for VS Code Remote SSH)"
    echo "----------------------------------------"
    echo ""

    local ssh_config_snippet="Host ${VM_NAME}
    HostName localhost
    Port ${SSH_PORT}
    User ${VM_USER}
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null"

    echo "Add this to your SSH config to connect with 'ssh ${VM_NAME}':"
    echo ""
    echo "$ssh_config_snippet"
    echo ""

    local config_exists=false
    if [[ -f "$ssh_config_file" ]] && grep -q "^Host ${VM_NAME}$" "$ssh_config_file" 2>/dev/null; then
        echo "[INFO] An entry for '${VM_NAME}' already exists in $ssh_config_file"
        config_exists=true
    fi

    if ! $config_exists; then
        read -p "Add this config to $ssh_config_file? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            mkdir -p "$ssh_config_dir"
            chmod 700 "$ssh_config_dir"
            echo "" >> "$ssh_config_file"
            echo "$ssh_config_snippet" >> "$ssh_config_file"
            chmod 600 "$ssh_config_file"
            echo "[OK] Added SSH config entry for '${VM_NAME}'"
        else
            echo "[SKIP] SSH config not modified"
        fi
    fi
    echo ""

    # Part 2: Authorized Keys Setup
    echo "----------------------------------------"
    echo "Part 2: Passwordless Login (SSH Keys)"
    echo "----------------------------------------"
    echo ""

    # Find available public keys
    local pub_keys=()
    if [[ -d "$HOME/.ssh" ]]; then
        while IFS= read -r -d '' key; do
            pub_keys+=("$key")
        done < <(find "$HOME/.ssh" -maxdepth 1 -name "*.pub" -type f -print0 2>/dev/null)
    fi

    if [[ ${#pub_keys[@]} -eq 0 ]]; then
        echo "[INFO] No SSH public keys found in ~/.ssh/"
        echo ""
        read -p "Generate a new SSH key pair (ed25519)? (Y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            local new_key="$HOME/.ssh/id_ed25519"
            if [[ -f "$new_key" ]]; then
                echo "[WARN] $new_key already exists (but no .pub file found)"
                echo "       This is unusual. Skipping key generation."
            else
                ssh-keygen -t ed25519 -f "$new_key" -N "" -C "${USER}@$(hostname)"
                if [[ -f "${new_key}.pub" ]]; then
                    pub_keys+=("${new_key}.pub")
                    echo "[OK] Generated new SSH key: $new_key"
                fi
            fi
        fi
    fi

    if [[ ${#pub_keys[@]} -eq 0 ]]; then
        echo "[INFO] No SSH keys available. Skipping key deployment."
        echo "       Password authentication (student/student) will continue to work."
    else
        echo "Available SSH public keys:"
        local i=1
        for key in "${pub_keys[@]}"; do
            local key_basename=$(basename "$key")
            local key_comment=$(awk '{print $3}' "$key" 2>/dev/null || echo "")
            echo "  [$i] $key_basename ${key_comment:+($key_comment)}"
            ((i++))
        done
        echo "  [s] Skip - don't deploy any key"
        echo ""

        local selected_key=""
        while true; do
            read -p "Select a key to deploy (1-${#pub_keys[@]}/s): " -r
            if [[ "$REPLY" =~ ^[Ss]$ ]]; then
                echo "[SKIP] No key deployed"
                break
            elif [[ "$REPLY" =~ ^[0-9]+$ ]] && [[ "$REPLY" -ge 1 ]] && [[ "$REPLY" -le ${#pub_keys[@]} ]]; then
                selected_key="${pub_keys[$((REPLY-1))]}"
                break
            else
                echo "Invalid selection. Enter a number 1-${#pub_keys[@]} or 's' to skip."
            fi
        done

        if [[ -n "$selected_key" ]]; then
            echo ""
            echo "[INFO] Deploying $(basename "$selected_key") to VM..."
            local pub_key_content
            pub_key_content=$(cat "$selected_key")

            # Use ssh to append the key to authorized_keys
            if ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                   "${VM_USER}@localhost" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub_key_content' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null; then
                echo "[OK] Key deployed successfully"

                # Verify the key works
                echo "[INFO] Verifying key-based authentication..."
                if ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                       -o PasswordAuthentication=no -o BatchMode=yes \
                       "${VM_USER}@localhost" "echo 'Key authentication successful'" 2>/dev/null; then
                    echo "[OK] Passwordless login is now configured!"
                else
                    echo "[WARN] Key deployed but verification failed."
                    echo "       Password login still works as fallback."
                fi
            else
                echo "[ERROR] Failed to deploy key. Is the VM running?"
                echo "        Password authentication (student/student) still works."
            fi
        fi
    fi
    echo ""

    # Part 3: GitLab Key Fetch (Optional)
    echo "----------------------------------------"
    echo "Part 3: GitLab Public Keys (Optional)"
    echo "----------------------------------------"
    echo ""
    echo "UFV GitLab publishes your SSH public keys at:"
    echo "  https://sc-gitlab.ufv.ca/USERNAME.keys"
    echo ""
    echo "This can be useful if you have keys configured on GitLab"
    echo "but not on this machine."
    echo ""

    read -p "Fetch and deploy keys from GitLab? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
        echo "Enter your UFV GitLab username."
        echo "(This may differ from your local username)"
        read -p "GitLab username: " gitlab_user

        if [[ -z "$gitlab_user" ]]; then
            echo "[SKIP] No username provided"
        else
            local gitlab_url="https://sc-gitlab.ufv.ca/${gitlab_user}.keys"
            echo "[INFO] Fetching keys from $gitlab_url..."

            local gitlab_keys
            gitlab_keys=$(curl -sf "$gitlab_url" 2>/dev/null)

            if [[ -z "$gitlab_keys" ]]; then
                echo "[WARN] No keys found at $gitlab_url"
                echo "       Check that your username is correct and you have"
                echo "       SSH keys configured in your GitLab profile."
            else
                local key_count
                key_count=$(echo "$gitlab_keys" | wc -l | tr -d ' ')
                echo "[INFO] Found $key_count key(s)"
                echo ""
                echo "Keys to deploy:"
                echo "$gitlab_keys" | while read -r line; do
                    # Show key type and comment (first and last fields)
                    echo "  - $(echo "$line" | awk '{print $1, $NF}')"
                done
                echo ""

                read -p "Deploy these keys to the VM? (Y/n) " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    # Escape single quotes in keys for shell command
                    local escaped_keys
                    escaped_keys=$(echo "$gitlab_keys" | sed "s/'/'\\\\''/g")

                    if ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
                           "${VM_USER}@localhost" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$escaped_keys' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" 2>/dev/null; then
                        echo "[OK] GitLab keys deployed successfully"
                    else
                        echo "[ERROR] Failed to deploy GitLab keys"
                    fi
                else
                    echo "[SKIP] GitLab keys not deployed"
                fi
            fi
        fi
    else
        echo "[SKIP] GitLab key fetch skipped"
    fi

    echo ""
    echo "=========================================="
    echo "  SSH Setup Complete"
    echo "=========================================="
    echo ""
    echo "You can now connect using:"
    if ! $config_exists && [[ -f "$ssh_config_file" ]] && grep -q "^Host ${VM_NAME}$" "$ssh_config_file" 2>/dev/null; then
        echo "  ssh ${VM_NAME}"
    fi
    echo "  ./provision.sh ssh"
    echo "  ssh -p ${SSH_PORT} ${VM_USER}@localhost"
    echo ""
    echo "Password authentication (student/student) always works as fallback."
}

# =============================================================================
# SESSION SETUP
# =============================================================================

run_session_setup() {
    local session="$1"
    local script="scripts/setup-session${session}.sh"

    if [[ ! -f "$script" ]]; then
        echo "[ERROR] Session setup script not found: $script"
        exit 1
    fi

    echo "[INFO] Running session $session setup..."
    bash "$script"
}

# =============================================================================
# STATUS DISPLAY
# =============================================================================

show_status() {
    echo "=== ${COURSE_NAME} Lab Environment Status ==="
    echo ""
    echo "Platform: $PLATFORM"
    echo "QEMU: $QEMU_SYSTEM"
    echo ""
    echo "VM Status:"
    if is_vm_running; then
        echo "  RUNNING"
        echo ""
        get_vm_info | sed 's/^/  /'
    else
        echo "  Not running"
    fi
    echo ""
    echo "Base Image:"
    if [[ -f "images/$ALPINE_IMAGE" ]]; then
        ls -lh "images/$ALPINE_IMAGE" | awk '{print "  " $5 " " $9}'
    else
        echo "  (not downloaded)"
    fi
    echo ""
    echo "VM Disk:"
    if [[ -f "images/${VM_NAME}.qcow2" ]]; then
        ls -lh "images/${VM_NAME}.qcow2" | awk '{print "  " $5 " " $9}'
    else
        echo "  (not created)"
    fi
    echo ""
    echo "Cloud-init ISO:"
    if [[ -f "cloudinit/cidata.iso" ]]; then
        echo "  Present (first boot pending)"
    else
        echo "  (already used or not created)"
    fi
}

# =============================================================================
# RESET VM
# =============================================================================

reset_vm() {
    echo "[WARN] This will delete your VM disk and all data!"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "images/${VM_NAME}.qcow2"
        rm -f cloudinit/cidata.iso cloudinit/meta-data
        rm -f "$LOGFILE"
        rm -f ".first-boot-done"
        echo "[OK] VM reset. Run './provision.sh init' to set up again."
    else
        echo "Cancelled."
    fi
}

# =============================================================================
# HELP
# =============================================================================

show_help() {
    cat << EOF
${COURSE_NAME} Lab Environment Provisioner

Usage: ./provision.sh <command> [options]

Commands:
  init              Download Alpine image and create cloud-init config
  start [qemu-args] Start the VM (auto-configures on first boot)
  stop [--force]    Stop the running VM
  stop-all          Force stop ALL QEMU instances (emergency)
  ssh               Connect to the VM via SSH
  monitor           Connect to QEMU monitor (for snapshots, VM control)
  setup-ssh         Configure SSH config and passwordless login
  session <N>       Run session-specific setup script
  status            Show VM and disk status
  reset             Delete VM disk and start fresh
  help              Show this help

Default VM Configuration:
  Memory: ${VM_MEMORY}
  CPUs:   ${VM_CPUS}
  Disk:   ${VM_DISK_SIZE}

Override defaults by passing QEMU arguments:
  ./provision.sh start -smp 4 -m 4G    # 4 CPUs, 4GB RAM

Hardware Acceleration:
  Linux:       ./provision.sh start -enable-kvm
  macOS Intel: ./provision.sh start -accel hvf
  macOS M1/M2: ./provision.sh start -accel hvf -cpu host
  Windows:     ./provision.sh start -accel whpx
  No accel:    ./provision.sh start (TCG emulation)

Nested Virtualization:
  For QEMU inside the VM, you need KVM passthrough on the host:
    ./provision.sh start -enable-kvm -cpu host
  Without this, nested VMs will use TCG (slower).

First-Time Setup:
  1. ./provision.sh init     # Download and configure
  2. ./provision.sh start    # Boot VM (wait for first-boot setup)
  3. ./provision.sh ssh      # Connect to VM
  4. ./verify-environment.sh # Verify setup inside VM

Credentials:
  Username: ${VM_USER}
  Password: student (change after first login)
  Sudo:     Passwordless

Pre-installed Tools:
  - Docker and containerd for containers
  - QEMU for nested virtualization
  - kubectl for Kubernetes management
  - strace, gdb for system debugging
  - lscpu, dmidecode for hardware inspection

QEMU Monitor (Session 3+):
  ./provision.sh monitor     # Connect to QEMU monitor

  Monitor commands for snapshots:
    savevm <name>            # Create internal snapshot
    loadvm <name>            # Restore internal snapshot
    info snapshots           # List snapshots
    system_powerdown         # ACPI shutdown

  SECURITY NOTE: The monitor uses an unauthenticated TCP connection
  on localhost:${MONITOR_PORT}. This is safe for local development but
  should never be exposed to external networks.

Monitoring:
  tail -f ${LOGFILE}         # Watch VM console output

EOF
}

# =============================================================================
# MAIN ENTRY POINT
# =============================================================================

main() {
    detect_platform

    case "$1" in
        init)
            echo "[INFO] Platform: $PLATFORM"
            echo "[INFO] ${COURSE_NAME} Lab Environment v$VERSION"
            echo ""
            check_dependencies
            mkdir -p images cloudinit
            download_alpine
            create_disk
            create_cloudinit_iso
            echo ""
            echo "[OK] Setup complete!"
            echo ""
            echo "Next steps:"
            echo "  1. ./provision.sh start"
            echo "  2. Wait for first-boot setup (may take several minutes)"
            echo "  3. ./provision.sh ssh"
            echo "  4. Run ./verify-environment.sh inside VM"
            echo ""
            echo "Credentials: ${VM_USER} / student"
            ;;
        start)
            check_dependencies
            shift
            start_vm "$@"
            ;;
        stop)
            if [[ "$2" == "--force" ]]; then
                stop_vm true
            else
                stop_vm false
            fi
            ;;
        stop-all)
            stop_all_vms
            ;;
        ssh)
            connect_ssh
            ;;
        monitor)
            monitor_vm
            ;;
        setup-ssh)
            setup_ssh_config
            ;;
        session)
            [[ -z "$2" ]] && { echo "[ERROR] Usage: ./provision.sh session <N>"; exit 1; }
            run_session_setup "$2"
            ;;
        status)
            show_status
            ;;
        reset)
            reset_vm
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo "${COURSE_NAME} Lab Environment v$VERSION"
            echo ""
            echo "Usage: ./provision.sh <command>"
            echo "Commands: init, start, stop, ssh, monitor, setup-ssh, status, reset, help"
            echo ""
            echo "Run './provision.sh help' for details"
            ;;
    esac
}

main "$@"
