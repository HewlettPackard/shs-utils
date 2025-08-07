# eth-tuning
Slingshot Host Software Ethernet Tuning

This utility script (`eth_tuning.sh`) is designed to optimize network interface parameters for high-performance networking, particularly for HSN (High-Speed Network) interfaces. It provides a comprehensive set of tools to get, set, and recommend optimal network parameters for both system-wide TCP settings and device-specific configurations.

## Purpose

The script aims to achieve optimal TCP performance by:

1. **System-wide TCP Buffer Optimization**
   - Configures optimal TCP receive and send buffer sizes
   - Sets appropriate TCP memory limits for both minimum and maximum values
   - Ensures proper memory allocation for network operations

2. **Device-specific Optimizations**
   - Configures optimal MTU (Maximum Transmission Unit) settings
   - Sets appropriate ring buffer sizes based on link speed (200G/400G)
   - Manages pause parameters for flow control
   - Optimizes queue lengths and number of queues
   - Implements XPS (Transmit Packet Steering) for efficient CPU utilization

3. **CPU Affinity and IRQ Management**
   - Distributes network processing across available CPU cores
   - Implements smart CPU core selection based on NUMA node locality
   - Manages IRQ balancing for optimal interrupt handling

## Key Features

### TCP Performance Optimizations

1. **TCP Buffer Sizes**
   - Configures optimal TCP receive and send buffer sizes
   - Sets appropriate minimum, default, and maximum values
   - Ensures efficient memory usage for network operations

2. **Socket Buffer Limits**
   - Sets system-wide receive and send buffer maximums
   - Optimizes memory allocation for network sockets
   - Prevents buffer overflow conditions

3. **Queue Management**
   - Configures optimal number of transmit and receive queues
   - Sets appropriate queue lengths for high-throughput scenarios
   - Implements efficient packet distribution across queues

### CPU and IRQ Optimizations

1. **XPS (Transmit Packet Steering)**
   - Distributes transmit queues across available CPU cores
   - Implements NUMA-aware CPU core selection
   - Provides flexible core count configuration
   - Ensures optimal CPU utilization for network processing

2. **IRQ Management**
   - Controls IRQ balancing service
   - Optimizes interrupt handling for network interfaces
   - Reduces CPU overhead for interrupt processing

### Device-specific Optimizations

1. **Link Speed Awareness**
   - Automatically detects link speed (200G/400G)
   - Applies appropriate ring buffer sizes
   - Sets optimal MTU values

2. **Flow Control**
   - Manages pause parameters
   - Implements appropriate flow control settings
   - Prevents packet loss during high traffic

## Usage

The script provides three main modes of operation:

1. **Get Mode**
   ```bash
   ./eth_tuning_new.sh --get value [--device <network_device>]
   ./eth_tuning_new.sh --get recommendation
   ```
   - Retrieves current network settings
   - Shows recommended values for optimal performance

2. **Set Mode**
   ```bash
   ./eth_tuning_new.sh --set value [--device <network_device>] [options]
   ./eth_tuning_new.sh --set recommendation [--device <network_device>]
   ```
   - Applies specific network settings
   - Can set recommended values automatically

3. **Dry Run Mode**
   ```bash
   ./eth_tuning_new.sh --set value [options] --dry-run
   ```
   - Shows commands that would be executed
   - Useful for previewing changes

## Performance Impact

The optimizations provided by this script can lead to:

1. **Improved Throughput**
   - Better utilization of available bandwidth
   - Reduced packet loss
   - More efficient packet processing

2. **Reduced Latency**
   - Optimized interrupt handling
   - Better CPU utilization
   - Efficient queue management

3. **Better Resource Utilization**
   - NUMA-aware CPU core distribution
   - Optimal memory allocation
   - Efficient buffer management

## Requirements

- Root privileges (must be run as root)
- Linux operating system
- Network interfaces to configure
- Basic network utilities (ip, ethtool, sysctl)

## Best Practices

1. **Initial Setup**
   - Start with recommended settings
   - Monitor performance metrics
   - Adjust based on specific workload requirements

2. **Performance Tuning**
   - Use dry-run mode to preview changes
   - Test changes in a controlled environment
   - Monitor system performance after changes

3. **Maintenance**
   - Regularly check current settings
   - Update parameters based on workload changes
   - Monitor system resources and network performance

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.
