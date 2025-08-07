#!/bin/bash
#
# © Copyright 2025 Hewlett Packard Enterprise Development LP
#

# Global variables
DRY_RUN=false
ACTION=""
MODE=""
DEVICE_NAME=""
CORES=""

# Base path for network devices
NET_PATH="/sys/class/net"
# Default affinity file
DEFAULT_AFFINITY="/proc/irq/default_smp_affinity"
# Default mask
DEFAULT_MASK=$(cat "$DEFAULT_AFFINITY")
# Default bitmask length
DEFAULT_BITMASK_LENGTH=$(echo $DEFAULT_MASK | awk -F',' '{print NF}')
# Page size
PAGESIZE=$(getconf PAGESIZE)

# Recommended values
RECOMMENDED_MTU=9000
RECOMMENDED_PAUSE="on"
RECOMMENDED_QUEUES=16
RECOMMENDED_RING_BUFFER_200G=4096
RECOMMENDED_RING_BUFFER_400G=8192
RECOMMENDED_TX_QUEUE_LENGTH=10000
RECOMMENDED_RX_BUFFER_MAX=16777216 #16MB
RECOMMENDED_TX_BUFFER_MAX=16777216 #16MB
RECOMMENDED_TCP_RMEM_MIN=$PAGESIZE
RECOMMENDED_TCP_RMEM_DEFAULT=$((PAGESIZE*32))
RECOMMENDED_TCP_RMEM_MAX=$RECOMMENDED_RX_BUFFER_MAX
RECOMMENDED_TCP_WMEM_MIN=$PAGESIZE
RECOMMENDED_TCP_WMEM_DEFAULT=$((PAGESIZE*32))
RECOMMENDED_TCP_WMEM_MAX=$RECOMMENDED_TX_BUFFER_MAX
RECOMMENDED_IRQ_ACTION="stop"

# Function to print usage
print_usage() {
    local scriptname
    scriptname=$(basename "$0")

    local usage="
Usage:
  $scriptname --get value [--device <network_device>]
  $scriptname --get recommendation
  $scriptname --set value [--device <network_device>] [options]
  $scriptname --set recommendation [--device <network_device>]
  Add --dry-run to any --set command to show commands without executing

Available Set Options:
  --mtu <value>              Set MTU value
  --pause <on|off>           Set pause parameters
  --rbuff <value>            Set ring buffer value
  --txqlen <value>           Set TX queue length
  --queue <value>            Set number of queues
  --bitmask                  Set XPS CPU bitmasks
  --cores <num>              (Optional) Override number of cores for XPS (can only be used with --bitmask)
                             Selects N cores from the NIC's local NUMA node, skipping the first (first is reserved for interrupts).
                             Example: if NIC's local NUMA node 1 has CPUs 16-31 and --cores 4 is given, selects CPUs 17–20.
                             With 16 queues and --cores 19, 3 queues get 2 CPUs, others get 1 CPU each.
  --rmem_max <value>         Set maximum receive buffer
  --wmem_max <value>         Set maximum send buffer
  --tcp_rmem <min def max>   Set TCP receive buffer sizes
  --tcp_wmem <min def max>   Set TCP send buffer sizes
  --irq <start|stop>         Control irqbalance service

Examples:
  Get Parameters:
    $scriptname --get value
    $scriptname --get value --device hsn0
    $scriptname --get recommendation
    $scriptname --get recommendation --device hsn0

  Set Parameters:
    $scriptname --set value --mtu 9000
    $scriptname --set value --pause on
    $scriptname --set value --bitmask
    $scriptname --set value --device hsn0 --mtu 9000
    $scriptname --set value --mtu 9000 --pause on --queue 16
    $scriptname --set value --bitmask --cores 4 --queue 16
    $scriptname --set value --device hsn0 --mtu 9000 --pause on --queue 16
    $scriptname --set recommendation
    $scriptname --set recommendation --device hsn0

  XPS/CPU Bitmask Examples:
    $scriptname --set value --bitmask
    $scriptname --set value --bitmask --cores 4
    $scriptname --set value --device hsn0 --bitmask
    $scriptname --set value --device hsn0 --bitmask --cores 4
    $scriptname --set value --device hsn0 --bitmask --cores 0
    $scriptname --set value --device hsn0 --mtu 9000 --pause on --bitmask --cores 4
    $scriptname --set value --device hsn0 --bitmask --cores 4 --queue 16

  Set All Options at Once:
    $scriptname --set value \\
      --mtu $RECOMMENDED_MTU \\
      --pause $RECOMMENDED_PAUSE \\
      --rbuff $RECOMMENDED_RING_BUFFER_200G \\
      --txqlen $RECOMMENDED_TX_QUEUE_LENGTH \\
      --queue $RECOMMENDED_QUEUES \\
      --bitmask \\
      --cores 4 \\
      --rmem_max $RECOMMENDED_RX_BUFFER_MAX \\
      --wmem_max $RECOMMENDED_TX_BUFFER_MAX \\
      --tcp_rmem $RECOMMENDED_TCP_RMEM_MIN $RECOMMENDED_TCP_RMEM_DEFAULT $RECOMMENDED_TCP_RMEM_MAX \\
      --tcp_wmem $RECOMMENDED_TCP_WMEM_MIN $RECOMMENDED_TCP_WMEM_DEFAULT $RECOMMENDED_TCP_WMEM_MAX \\
      --irq $RECOMMENDED_IRQ_ACTION

  Dry Run Examples:
    $scriptname --set value --mtu 9000 --dry-run
    $scriptname --set value --bitmask --cores 4 --dry-run
    $scriptname --set recommendation --dry-run
    $scriptname --set value --device hsn0 --mtu 9000 --dry-run
    $scriptname --set value --device hsn0 --bitmask --cores 4 --dry-run
    $scriptname --set value --device hsn0 \\
      --mtu $RECOMMENDED_MTU \\
      --pause $RECOMMENDED_PAUSE \\
      --rbuff $RECOMMENDED_RING_BUFFER_200G \\
      --txqlen $RECOMMENDED_TX_QUEUE_LENGTH \\
      --queue $RECOMMENDED_QUEUES \\
      --bitmask \\
      --rmem_max $RECOMMENDED_RX_BUFFER_MAX \\
      --wmem_max $RECOMMENDED_TX_BUFFER_MAX \\
      --tcp_rmem $RECOMMENDED_TCP_RMEM_MIN $RECOMMENDED_TCP_RMEM_DEFAULT $RECOMMENDED_TCP_RMEM_MAX \\
      --tcp_wmem $RECOMMENDED_TCP_WMEM_MIN $RECOMMENDED_TCP_WMEM_DEFAULT $RECOMMENDED_TCP_WMEM_MAX \\
      --irq $RECOMMENDED_IRQ_ACTION \\
      --dry-run
"

    printf '%s\n' "$usage"
    exit 255
}

# Function to count CPUs in a comma-separated list
count_cpus() {
    local cpu_list="$1"
    local IFS=','
    read -ra cpus <<< "$cpu_list"
    echo "${#cpus[@]}"
}

# Function to convert CPU list to bitmask
cpulist_to_bitmask() {
    local cpus
    IFS=',' read -ra cpus <<< "$1"
    local bitmask_array=()
    local max_bits=$((DEFAULT_BITMASK_LENGTH * 32))

    # Initialize bitmask array with zeros
    for ((i = 0; i < DEFAULT_BITMASK_LENGTH; i++))
    do
        bitmask_array[i]=0
    done

    # Set the corresponding bit for each CPU
    for cpu in "${cpus[@]}"
    do
        bit_index=$((cpu % max_bits))
        array_index=$((bit_index / 32))
        bit_position=$((bit_index % 32))

        bitmask_array[array_index]=$((bitmask_array[array_index] | (1 << bit_position)))
    done

    # Convert bitmask array to hexadecimal format
    hex_mask=""
    for ((i = DEFAULT_BITMASK_LENGTH - 1; i >= 0; i--))
    do
        #hex_mask+=`printf "%08x," ${bitmask_array[i]}`
        hex_mask+=$(printf "%08x," "${bitmask_array[i]}")
    done

    # Remove the trailing comma
    echo "${hex_mask%,}"
}

# Function to set XPS bitmask
set_xps_bitmask() {
    local device_name="$1"
    local queue_num="$2"
    local bitmask="$3"
    local xps_path="/sys/class/net/$device_name/queues/tx-$queue_num/xps_cpus"

    if [ ! -f "$xps_path" ]; then
        echo "Error: XPS path not found: $xps_path"
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        echo "echo $bitmask > $xps_path"
    else
        echo "$bitmask" > "$xps_path"
        if [ $? -eq 0 ]; then
            echo "Successfully set XPS bitmask for $device_name queue $queue_num"
        else
            echo "Failed to set XPS bitmask for $device_name queue $queue_num"
        fi
    fi
}

# Function to get XPS bitmask
get_xps_bitmask() {
    local device_name="$1"
    local queue_num="$2"
    local cpus="$3"
    local bitmask="$4"
    local xps_path="/sys/class/net/$device_name/queues/tx-$queue_num/xps_cpus"

    if [ ! -f "$xps_path" ]; then
        echo "Error: XPS path not found: $xps_path"
        return 1
    fi

    if [ "$MODE" = "value" ]; then
        # For value mode, just show current bitmask
        echo "cat $xps_path: $(cat $xps_path)"
    else
        # For recommendation mode, show calculated bitmask
        echo "$xps_path: $bitmask"
    fi
}

# Function to split CPUs and handle XPS settings
split_cpus() {
    local cpu_list="$1"
    local num_queues="$2"

    local IFS=','
    read -ra cpus <<< "$cpu_list"
    local total_cpus=${#cpus[@]}

    # If CORES is specified, take only that many CPUs
    if [ -n "$CORES" ]; then
        # Skip first core and take next N cores from the list
        local new_cpu_list=""
        for ((i=1; i<(CORES+1) && i<total_cpus; i++)); do
            if [ -n "$new_cpu_list" ]; then
                new_cpu_list+=","
            fi
            new_cpu_list+="${cpus[i]}"
        done
        cpu_list="$new_cpu_list"
        total_cpus=$CORES
    elif [ "$MODE" = "recommendation" ]; then
        total_cpus=$num_queues
    fi

    # If we have fewer CPUs than queues, use all CPUs for each queue
    if [ $total_cpus -lt $num_queues ]; then
        local bitmask=$(cpulist_to_bitmask "$cpu_list")

        for ((i=0; i<num_queues; i++)); do
            if [ "$ACTION" = "get" ]; then
                get_xps_bitmask "$device_name" "$i" "$cpu_list" "$bitmask"
            elif [ "$ACTION" = "set" ]; then
                set_xps_bitmask "$device_name" "$i" "$bitmask"
            fi
        done
        return
    fi

    # Normal distribution when we have enough CPUs
    local cpus_per_queue=$((total_cpus / num_queues))
    local remainder=$((total_cpus % num_queues))

    local start=0
    local bitmasks=()

    for ((i=0; i<num_queues; i++)); do
        local chunk_size=$cpus_per_queue
        if [ $i -lt $remainder ]; then
            ((chunk_size++))
        fi

        local end=$((start + chunk_size))
        local chunk=""

        for ((j=start; j<end; j++)); do
            if [ -n "$chunk" ]; then
                chunk+=","
            fi
            chunk+="${cpus[j]}"
        done

        local bitmask=$(cpulist_to_bitmask "$chunk")
        bitmasks[$i]="$bitmask"

        if [ "$ACTION" = "get" ]; then
            get_xps_bitmask "$device_name" "$i" "$chunk" "$bitmask"
        fi

        start=$end
    done

    if [ "$ACTION" = "set" ]; then
        for ((i=0; i<num_queues; i++)); do
            set_xps_bitmask "$device_name" "$i" "${bitmasks[$i]}"
        done
    fi
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

# Function to show system-wide settings
show_system_wide_settings() {
    echo -e "\n=== System-wide Settings ==="
    echo "Receive Buffer Maximum:"
    echo "Command: sysctl net.core.rmem_max"
    sysctl net.core.rmem_max

    echo "Send Buffer Maximum:"
    echo "Command: sysctl net.core.wmem_max"
    sysctl net.core.wmem_max

    echo "TCP Receive Buffer:"
    echo "Command: sysctl net.ipv4.tcp_rmem"
    sysctl net.ipv4.tcp_rmem

    echo "TCP Send Buffer:"
    echo "Command: sysctl net.ipv4.tcp_wmem"
    sysctl net.ipv4.tcp_wmem

    echo "NUMA Node CPU Count (Local to HSN devices):"
    echo "Command: for nic in /sys/class/net/hsn*; do [ -e \"\$nic\" ] && echo \"Node \$(cat \$nic/device/numa_node): \$(numactl --hardware | grep -A1 \"node \$(cat \$nic/device/numa_node) cpus:\" | head -n1 | awk '{print NF-3 \" CPUs\"}') [\$(basename \$nic)]\"; done | sort -u"
    for nic in /sys/class/net/hsn*; do
        [ -e "$nic" ] && echo "Node $(cat $nic/device/numa_node): $(numactl --hardware | grep -A1 "node $(cat $nic/device/numa_node) cpus:" | head -n1 | awk '{print NF-3 " CPUs"}') [$(basename $nic)]"
    done | sort -u
}

# Function to get network information
get_network_info() {
    local device=$1
    device_name=$device  # Set the global device_name variable

    # Check if device exists
    if ! ip link show "$device" >/dev/null 2>&1; then
        echo "Error: Network device $device not found"
        return 1
    fi

    echo "=== Network Device Information for $device ==="
    echo -e "\n1. IP Link Show (MTU):"
    echo "Command: ip link show $device | grep -i 'mtu'"
    ip link show "$device" | grep -i 'mtu'

    echo -e "\n2. Channel Information:"
    echo "Command: ethtool -l $device"
    ethtool -l "$device" 2>/dev/null || echo "Channel information not available"

    echo -e "\n3. Ring Buffer Information:"
    echo "Command: ethtool -g $device"
    ethtool -g "$device" 2>/dev/null || echo "Ring buffer information not available"

    echo -e "\n4. Pause Parameters:"
    echo "Command: ethtool -a $device"
    ethtool -a "$device" 2>/dev/null || echo "Pause parameters not available"

    echo -e "\n5. Queue Length:"
    echo "Command: ip link show dev $device | grep qlen | sed 's|^.*qlen|qlen|g'"
    ip link show dev "$device" | grep qlen | sed 's|^.*qlen|qlen|g' || echo "Queue length information not available"

    # Add XPS information using split_cpus
    echo -e "\n6. XPS Settings:"
    echo "Command:"
    local numa_node=$(cat "/sys/class/net/$device/device/numa_node")
    local cpu_list=$(numactl --hardware | grep -A1 "node $numa_node cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')
    local tx_queues=$(ethtool -l "$device" 2>/dev/null | grep -A4 "Current hardware settings:" | grep "TX" | awk '{print $NF}')
    split_cpus "$cpu_list" "$tx_queues"
}

# Function to show IRQ balance status
show_irq_balance() {
    echo -e "\n=== IRQ Balance Status ==="
    echo "Command: systemctl status irqbalance"
    systemctl status irqbalance
}

# Function to process all HSN interfaces
process_all_interfaces() {
    echo -e "\nChecking all HSN interfaces..."
    # Get all HSN interfaces
    local interfaces=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | grep -E '^hsn[0-9]+')

    if [[ -z "$interfaces" ]]; then
        echo "No HSN interfaces found. Available interfaces are:"
        ip -o link show | awk -F': ' '$2 != "lo" {print $2}'
        return 1
    fi

    for interface in $interfaces; do
        get_network_info "$interface"
    done
}

# Function to set MTU value
set_mtu() {
    local device=$1
    local mtu_value=$2
    if $DRY_RUN; then
        echo "ip link set dev $device mtu $mtu_value"
    else
        echo "Setting MTU for $device to $mtu_value"
        ip link set dev "$device" mtu "$mtu_value"
    fi
}

# Function to set pause parameters
set_pause() {
    local device=$1
    local pause_value=$2
    if $DRY_RUN; then
        echo "ethtool -A $device autoneg off rx $pause_value tx $pause_value"
    else
        echo "Setting pause parameters for $device to $pause_value"
        ethtool -A "$device" autoneg off rx "$pause_value" tx "$pause_value"
    fi
}

# Function to set ring buffer
set_ring_buffer() {
    local device=$1
    local rb_value=$2
    if $DRY_RUN; then
        echo "ethtool -G $device rx $rb_value tx $rb_value"
    else
        echo "Setting ring buffer for $device to $rb_value"
        ethtool -G "$device" rx "$rb_value" tx "$rb_value"
    fi
}

# Function to set TX queue length
set_txqlen() {
    local device=$1
    local qlen_value=$2
    if $DRY_RUN; then
        echo "ip link set dev $device txqueuelen $qlen_value"
    else
        echo "Setting TX queue length for $device to $qlen_value"
        ip link set dev "$device" txqueuelen "$qlen_value"
    fi
}

# Function to set number of queues
set_queues() {
    local device=$1
    local queue_value=$2
    if $DRY_RUN; then
        echo "ethtool -L $device rx $queue_value tx $queue_value"
    else
        echo "Setting number of queues for $device to $queue_value"
        ethtool -L "$device" tx "$queue_value" rx "$queue_value"
    fi
}

# Function to set rmem_max
set_rmem_max() {
    local max_value=$1
    if $DRY_RUN; then
        echo "sysctl -w net.core.rmem_max=$max_value"
    else
        echo "Setting rmem_max to $max_value"
        sysctl -w net.core.rmem_max="$max_value"
    fi
}

# Function to set wmem_max
set_wmem_max() {
    local max_value=$1
    if $DRY_RUN; then
        echo "sysctl -w net.core.wmem_max=$max_value"
    else
        echo "Setting wmem_max to $max_value"
        sysctl -w net.core.wmem_max="$max_value"
    fi
}

# Function to set tcp_rmem
set_tcp_rmem() {
    local min=$1
    local default=$2
    local max=$3
    if $DRY_RUN; then
        echo "sysctl -w net.ipv4.tcp_rmem=\"$min $default $max\""
    else
        echo "Setting tcp_rmem to $min $default $max"
        sysctl -w net.ipv4.tcp_rmem="$min $default $max"
    fi
}

# Function to set tcp_wmem
set_tcp_wmem() {
    local min=$1
    local default=$2
    local max=$3
    if $DRY_RUN; then
        echo "sysctl -w net.ipv4.tcp_wmem=\"$min $default $max\""
    else
        echo "Setting tcp_wmem to $min $default $max"
        sysctl -w net.ipv4.tcp_wmem="$min $default $max"
    fi
}

# Function to control irqbalance service
set_irq_balance() {
    local action=$1
    if $DRY_RUN; then
        echo "systemctl $action irqbalance"
    else
        echo "Setting irqbalance service to $action"
        systemctl "$action" irqbalance
    fi
}

# Function to get link speed
get_link_speed() {
    local device=$1
    if [[ "$(ethtool $device | grep 'Speed' | xargs | awk '{print $NF}')" == *"200000Mb/s"* ]]; then
        echo "200G"
    else
        echo "400G"
    fi
}

# Function to get recommended settings
get_recommended_settings() {
    echo "=== Recommended Network Settings ==="
    echo "The following settings are recommended for optimal performance:"
    echo
    echo "MTU:                $RECOMMENDED_MTU       # Maximum Transmission Unit"
    echo "Pause:              $RECOMMENDED_PAUSE         # Enable pause parameters"
    echo "Total Queues:       $RECOMMENDED_QUEUES         # Number of tx,rx queues"
    echo "TX Queue Length:    $RECOMMENDED_TX_QUEUE_LENGTH      # Transmit queue length"
    echo "RX Buffer Max:      $RECOMMENDED_RX_BUFFER_MAX   # Maximum receive buffer (16MB)"
    echo "TX Buffer Max:      $RECOMMENDED_TX_BUFFER_MAX   # Maximum transmit buffer (16MB)"
    echo "IRQ Balance:        $RECOMMENDED_IRQ_ACTION       # Disable IRQ balancing"
    echo "TCP Receive Buffer: $RECOMMENDED_TCP_RMEM_MIN $RECOMMENDED_TCP_RMEM_DEFAULT $RECOMMENDED_TCP_RMEM_MAX   # TCP receive buffer (min,default,max)"
    echo "TCP Send Buffer:    $RECOMMENDED_TCP_WMEM_MIN $RECOMMENDED_TCP_WMEM_DEFAULT $RECOMMENDED_TCP_WMEM_MAX   # TCP send buffer (min,default,max)"
    echo "Ring Buffer:        200G: $RECOMMENDED_RING_BUFFER_200G, 400G: $RECOMMENDED_RING_BUFFER_400G   # Ring buffer size"
    echo "XPS:                see below  # CPUs from the device's NUMA node (skipping first core reserved"
    echo "                                 for interrupts) are distributed across TX queues. In recommended"
    echo "                                 settings, each queue gets exactly one CPU."

    # Get XPS recommendations using split_cpus
    ACTION="get"
    MODE="recommendation"

    if [[ -n "$DEVICE_NAME" ]]; then
        # Process only specified device
        if [[ ! -e "$NET_PATH/$DEVICE_NAME" ]]; then
            echo "Error: Device $DEVICE_NAME not found"
            return 1
        fi
        device_name="$DEVICE_NAME"
        numa_node=$(cat "$NET_PATH/$device_name/device/numa_node")
        cpu_list=$(numactl --hardware | grep -A1 "node $numa_node cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')

        # Calculate and show bitmasks for all recommended queues
        local cpus_array=()
        IFS=',' read -ra cpus_array <<< "$cpu_list"
        local total_cpus=${#cpus_array[@]}

        # Skip first core (reserved for interrupts)
        for ((i=1; i<RECOMMENDED_QUEUES+1 && i<total_cpus; i++)); do
            local queue_num=$((i-1))
            local bitmask=$(cpulist_to_bitmask "${cpus_array[i]}")
            echo "/sys/class/net/$device_name/queues/tx-$queue_num/xps_cpus: $bitmask"
        done
    else
        # Process all HSN devices
        for nic in "$NET_PATH"/hsn*; do
            [ -e "$nic" ] || { echo "No HSN devices found"; return 1; }
            device_name=$(basename "$nic")
            numa_node=$(cat "$nic/device/numa_node")
            cpu_list=$(numactl --hardware | grep -A1 "node $numa_node cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')

            # Calculate and show bitmasks for all recommended queues
            local cpus_array=()
            IFS=',' read -ra cpus_array <<< "$cpu_list"
            local total_cpus=${#cpus_array[@]}

            # Skip first core (reserved for interrupts)
            for ((i=1; i<RECOMMENDED_QUEUES+1 && i<total_cpus; i++)); do
                local queue_num=$((i-1))
                local bitmask=$(cpulist_to_bitmask "${cpus_array[i]}")
                echo "/sys/class/net/$device_name/queues/tx-$queue_num/xps_cpus: $bitmask"
            done
        done
    fi

    echo
    echo "To apply these settings, use:"
    echo "$0 --set recommendation [--device <hsn_device>] [--dry-run]"
}

# Function to handle all set operations
set_parameters() {
    local device=$1
    shift
    local args=("$@")  # Store all arguments in an array

    # Check if any set options were provided
    local has_set_options=false
    for arg in "${args[@]}"; do
        case $arg in
            --mtu|--pause|--rbuff|--txqlen|--queue|--rmem_max|--wmem_max|--tcp_rmem|--tcp_wmem|--irq|--bitmask)
                has_set_options=true
                break
                ;;
        esac
    done

    if ! $has_set_options; then
        echo "Error: No set options provided. Must specify at least one option (--mtu, --pause, --bitmask, etc.)"
        print_usage
    fi

    # Set system-wide parameters first if they are specified
    local i=0
    while [ $i -lt ${#args[@]} ]; do
        case "${args[$i]}" in
            --rmem_max)
                if [ $((i+1)) -lt ${#args[@]} ]; then
                    set_rmem_max "${args[$((i+1))]}"
                fi
                i=$((i+2))
                ;;
            --wmem_max)
                if [ $((i+1)) -lt ${#args[@]} ]; then
                    set_wmem_max "${args[$((i+1))]}"
                fi
                i=$((i+2))
                ;;
            --tcp_rmem)
                if [ $((i+3)) -lt ${#args[@]} ]; then
                    set_tcp_rmem "${args[$((i+1))]}" "${args[$((i+2))]}" "${args[$((i+3))]}"
                fi
                i=$((i+4))
                ;;
            --tcp_wmem)
                if [ $((i+3)) -lt ${#args[@]} ]; then
                    set_tcp_wmem "${args[$((i+1))]}" "${args[$((i+2))]}" "${args[$((i+3))]}"
                fi
                i=$((i+4))
                ;;
            --irq)
                if [ $((i+1)) -lt ${#args[@]} ]; then
                    set_irq_balance "${args[$((i+1))]}"
                fi
                i=$((i+2))
                ;;
            *)
                i=$((i+1))
                ;;
        esac
    done

    # Get list of interfaces to process
    local interfaces
    if [[ -z "$device" ]]; then
        if ! $DRY_RUN; then
            echo "No device specified, applying device specific settings to all HSN interfaces..."
        fi
        interfaces=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | grep -E '^hsn[0-9]+')

        if [[ -z "$interfaces" ]]; then
            echo "No HSN interfaces found. Available interfaces are:"
            ip -o link show | awk -F': ' '$2 != "lo" {print $2}'
            return 1
        fi
    else
        interfaces="$device"
    fi

    # Process each interface
    for interface in $interfaces; do
        if ! $DRY_RUN; then
            echo -e "\nConfiguring $interface..."
        fi
        device_name="$interface"  # Set global device_name

        # Process all set parameters for this interface
        i=0
        while [ $i -lt ${#args[@]} ]; do
            case "${args[$i]}" in
                --dry-run)
                    i=$((i+1))
                    ;;
                --bitmask)
                    # XPS settings will be handled after other parameters
                    i=$((i+1))
                    ;;
                --mtu)
                    if [ $((i+1)) -lt ${#args[@]} ]; then
                        set_mtu "$interface" "${args[$((i+1))]}"
                    fi
                    i=$((i+2))
                    ;;
                --pause)
                    if [ $((i+1)) -lt ${#args[@]} ]; then
                        set_pause "$interface" "${args[$((i+1))]}"
                    fi
                    i=$((i+2))
                    ;;
                --rbuff)
                    if [ $((i+1)) -lt ${#args[@]} ]; then
                        set_ring_buffer "$interface" "${args[$((i+1))]}"
                    fi
                    i=$((i+2))
                    ;;
                --txqlen)
                    if [ $((i+1)) -lt ${#args[@]} ]; then
                        set_txqlen "$interface" "${args[$((i+1))]}"
                    fi
                    i=$((i+2))
                    ;;
                --queue)
                    if [ $((i+1)) -lt ${#args[@]} ]; then
                        set_queues "$interface" "${args[$((i+1))]}"
                    fi
                    i=$((i+2))
                    ;;
                --cores)
                    # Just store the value, XPS settings are handled separately
                    i=$((i+2))
                    ;;
                --rmem_max|--wmem_max|--irq)
                    # Skip system-wide parameters as they were already set
                    i=$((i+2))
                    ;;
                --tcp_rmem|--tcp_wmem)
                    # Skip system-wide parameters as they were already set (these have 3 values)
                    i=$((i+4))
                    ;;
                *)
                    echo "Error: Unknown parameter ${args[$i]}"
                    exit 1
                    ;;
            esac
        done

        # Handle XPS settings only if --bitmask was specified
        for arg in "${args[@]}"; do
            if [ "$arg" = "--bitmask" ]; then
                local numa_node=$(cat "/sys/class/net/$interface/device/numa_node")
                local cpu_list=$(numactl --hardware | grep -A1 "node $numa_node cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')
                local tx_queues=$(ethtool -l "$interface" 2>/dev/null | grep -A4 "Current hardware settings:" | grep "TX" | awk '{print $NF}')
                split_cpus "$cpu_list" "$tx_queues"
                break
            fi
        done
    done
}

# Function to set recommended settings
set_recommended_settings() {
    local device=$1

    # Check if any HSN interfaces exist
    local interfaces=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2}' | grep -E '^hsn[0-9]+')
    if [[ -z "$interfaces" ]]; then
        echo "Error: No HSN interfaces found. Available interfaces are:"
        ip -o link show | awk -F': ' '$2 != "lo" {print $2}'
        return 1
    fi

    # Set system-wide parameters first
    if ! $DRY_RUN; then
        echo "Setting system-wide parameters"
    fi
    set_rmem_max "$RECOMMENDED_RX_BUFFER_MAX"
    set_wmem_max "$RECOMMENDED_TX_BUFFER_MAX"
    set_tcp_rmem "$RECOMMENDED_TCP_RMEM_MIN" "$RECOMMENDED_TCP_RMEM_DEFAULT" "$RECOMMENDED_TCP_RMEM_MAX"
    set_tcp_wmem "$RECOMMENDED_TCP_WMEM_MIN" "$RECOMMENDED_TCP_WMEM_DEFAULT" "$RECOMMENDED_TCP_WMEM_MAX"
    set_irq_balance "$RECOMMENDED_IRQ_ACTION"

    if [[ -n "$device" ]]; then
        # Check if specified device exists
        if [[ ! -e "$NET_PATH/$device" ]]; then
            echo "Error: Device $device not found"
            return 1
        fi
        device_name="$device"  # Set global device_name
        if ! $DRY_RUN; then
            echo "Applying to device: $device"
        fi

        local link_speed=$(get_link_speed $device)
        local ring_buffer_size
        if [[ "$link_speed" == "200G" ]]; then
            ring_buffer_size=$RECOMMENDED_RING_BUFFER_200G
        else
            ring_buffer_size=$RECOMMENDED_RING_BUFFER_400G
        fi

        # Set device parameters
        set_mtu "$device" "$RECOMMENDED_MTU"
        set_pause "$device" "$RECOMMENDED_PAUSE"
        set_queues "$device" "$RECOMMENDED_QUEUES"
        set_ring_buffer "$device" "$ring_buffer_size"
        set_txqlen "$device" "$RECOMMENDED_TX_QUEUE_LENGTH"

        # Set XPS bitmask for all recommended queues
        local numa_node=$(cat "/sys/class/net/$device/device/numa_node")
        local cpu_list=$(numactl --hardware | grep -A1 "node $numa_node cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')
        local cpus_array=()
        IFS=',' read -ra cpus_array <<< "$cpu_list"
        local total_cpus=${#cpus_array[@]}

        if ! $DRY_RUN; then
            echo "Setting XPS bitmasks for $device"
        fi

        # Skip first core (reserved for interrupts)
        for ((i=1; i<RECOMMENDED_QUEUES+1 && i<total_cpus; i++)); do
            local queue_num=$((i-1))
            local bitmask=$(cpulist_to_bitmask "${cpus_array[i]}")
            local xps_path="/sys/class/net/$device/queues/tx-$queue_num/xps_cpus"

            if $DRY_RUN; then
                echo "echo $bitmask > $xps_path"
            else
                if [ -f "$xps_path" ]; then
                    echo "$bitmask" > "$xps_path"
                fi
            fi
        done

        if [ $RECOMMENDED_QUEUES -ge $total_cpus ] && ! $DRY_RUN; then
            echo -e "\nWarning: Recommended queue count ($RECOMMENDED_QUEUES) is greater than available CPUs in NUMA node ($total_cpus)"
            echo "         This may impact performance. Consider reducing queue count or using a different NUMA node."
        fi
    else
        if ! $DRY_RUN; then
            echo "Applying device specific settings to all HSN interfaces..."
        fi

        for interface in $interfaces; do
            if ! $DRY_RUN; then
                echo "Applying to device: $interface"
            fi

            local interface_link_speed=$(get_link_speed $interface)
            local interface_ring_buffer_size
            if [[ "$interface_link_speed" == "200G" ]]; then
                interface_ring_buffer_size=$RECOMMENDED_RING_BUFFER_200G
            else
                interface_ring_buffer_size=$RECOMMENDED_RING_BUFFER_400G
            fi

            # Set device parameters
            set_mtu "$interface" "$RECOMMENDED_MTU"
            set_pause "$interface" "$RECOMMENDED_PAUSE"
            set_queues "$interface" "$RECOMMENDED_QUEUES"
            set_ring_buffer "$interface" "$interface_ring_buffer_size"
            set_txqlen "$interface" "$RECOMMENDED_TX_QUEUE_LENGTH"

            # Set XPS bitmask for all recommended queues
            local numa_node=$(cat "/sys/class/net/$interface/device/numa_node")
            local cpu_list=$(numactl --hardware | grep -A1 "node $numa_node cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')
            local cpus_array=()
            IFS=',' read -ra cpus_array <<< "$cpu_list"
            local total_cpus=${#cpus_array[@]}

            if ! $DRY_RUN; then
                echo "Setting XPS bitmasks for $interface"
            fi

            # Skip first core (reserved for interrupts)
            for ((i=1; i<RECOMMENDED_QUEUES+1 && i<total_cpus; i++)); do
                local queue_num=$((i-1))
                local bitmask=$(cpulist_to_bitmask "${cpus_array[i]}")
                local xps_path="/sys/class/net/$interface/queues/tx-$queue_num/xps_cpus"

                if $DRY_RUN; then
                    echo "echo $bitmask > $xps_path"
                else
                    if [ -f "$xps_path" ]; then
                        echo "$bitmask" > "$xps_path"
                    fi
                fi
            done

            if [ $RECOMMENDED_QUEUES -ge $total_cpus ] && ! $DRY_RUN; then
                echo -e "\nWarning: Recommended queue count ($RECOMMENDED_QUEUES) is greater than available CPUs in NUMA node ($total_cpus)"
                echo "         This may impact performance. Consider reducing queue count or using a different NUMA node."
            fi
        done
    fi

    if ! $DRY_RUN; then
        echo -e "\nAll recommended settings have been applied."
    fi
}

# Main function to handle script execution
main() {
    local GET=false
    local SET=false
    local GET_VALUE=""
    local SET_VALUE=""
    local REMAINING_ARGS=()

    # Handle help
    if [[ $# -eq 0 || "$1" == "--help" || "$1" == "-h" ]]; then
        print_usage
    fi

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --get)
                GET=true
                ACTION="get"
                if [[ -n "$2" ]]; then
                    if [[ "$2" == "value" || "$2" == "recommendation" ]]; then
                        GET_VALUE="$2"
                        MODE="$2"
                        shift 2
                    else
                        echo "Error: --get requires 'value' or 'recommendation' as parameter"
                        print_usage
                    fi
                else
                    echo "Error: --get requires a parameter"
                    print_usage
                fi
                ;;
            --set)
                SET=true
                ACTION="set"
                if [[ -n "$2" ]]; then
                    if [[ "$2" == "value" || "$2" == "recommendation" ]]; then
                        SET_VALUE="$2"
                        MODE="$2"
                        shift 2
                    else
                        echo "Error: --set requires 'value' or 'recommendation' as parameter"
                        print_usage
                    fi
                else
                    echo "Error: --set requires a parameter"
                    print_usage
                fi
                ;;
            --device)
                if [[ -n "$2" ]]; then
                    DEVICE_NAME="$2"
                    shift 2
                else
                    echo "Error: --device requires a network interface name"
                    print_usage
                fi
                ;;
            --cores)
                if [[ -n "$2" ]]; then
                    if [[ "$MODE" = "recommendation" ]]; then
                        echo "Error: --cores cannot be used with recommendation mode"
                        print_usage
                    fi
                    # Validate cores parameter against NUMA node CPUs
                    if [[ -n "$DEVICE_NAME" ]]; then
                        local numa_node=$(cat "/sys/class/net/$DEVICE_NAME/device/numa_node")
                        local cpu_list=$(numactl --hardware | grep -A1 "node $numa_node cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')
                        local total_cpus=$(echo "$cpu_list" | tr ',' '\n' | wc -l)
                        if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -ge "$total_cpus" ]]; then
                            echo "Error: --cores value must be a number less than $total_cpus (available CPUs in NUMA node $numa_node)"
                            print_usage
                        fi
                    else
                        # If no device specified, validate against first NUMA node's CPUs
                        local cpu_list=$(numactl --hardware | grep -A1 "node 0 cpus:" | head -n1 | cut -d":" -f2 | xargs | sed 's| |,|g')
                        local total_cpus=$(echo "$cpu_list" | tr ',' '\n' | wc -l)
                        if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -ge "$total_cpus" ]]; then
                            echo "Error: --cores value must be a number less than $total_cpus (available CPUs in NUMA node 0)"
                            print_usage
                        fi
                    fi
                    CORES="$2"
                    shift 2
                else
                    echo "Error: Number of cores required with --cores"
                    print_usage
                fi
                ;;
            *)
                if $SET && [[ "$SET_VALUE" == "value" ]]; then
                    REMAINING_ARGS+=("$1")
                    shift
                else
                    print_usage
                fi
                ;;
        esac
    done

    # Validate arguments
    if ! $GET && ! $SET; then
        echo "Error: Must specify either --get value/recommendation or --set value"
        print_usage
    fi

    # Check root privileges
    check_root

    if $GET; then
        if [[ "$GET_VALUE" == "recommendation" ]]; then
            get_recommended_settings
        else
            show_irq_balance
            show_system_wide_settings
            if [[ -z "$DEVICE_NAME" ]]; then
                process_all_interfaces
            else
                get_network_info "$DEVICE_NAME"
            fi
        fi
    elif $SET && [[ "$SET_VALUE" == "recommendation" ]]; then
        set_recommended_settings "$DEVICE_NAME"
    elif $SET && [[ "$SET_VALUE" == "value" ]]; then
        set_parameters "$DEVICE_NAME" "${REMAINING_ARGS[@]}"
    fi
}

# Call the main function with all command line arguments
main "$@"
