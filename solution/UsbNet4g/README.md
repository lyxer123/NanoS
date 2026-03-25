# USB Network Bridge Solution

## Overview

This solution provides a comprehensive approach to migrate from the existing W5500 SPI Ethernet to a USB-based network architecture using CH397A USB Ethernet adapter and USB 4G CAT1 module, connected via USB Hub to ESP32S3.

## Architecture Analysis

### Current W5500 Implementation

- **Connection**: SPI interface to ESP32S3
- **Role**: Data forwarding interface (LAN side)
- **Configuration**: DHCP server
- **Driver**: `bridge_eth.c` with SPI Ethernet support

### New USB-based Architecture

```
ESP32S3 (USB OTG Host)
    ↓
USB Hub (4-port)
    ├─→ CH397A USB Ethernet (LAN interface)
    ├─→ USB 4G CAT1 module (WAN interface)
    ├─→ STM32F072C8T6 expansion board (functional extension)
    └─→ (reserved port)
```

## CH397A USB ECM Protocol Analysis

### CH397A Technical Features

- **Protocol**: USB CDC-ECM (Ethernet Control Model)
- **Speed**: 10/100Mbps Ethernet
- **Interface**: USB 2.0 Full Speed
- **Compatibility**: Standard USB ECM class device

### USB ECM Protocol Compatibility

#### Existing Support in ESP-IoT-Bridge

The current `bridge_usb.c` already has ECM support:

```c
static esp_err_t esp_bridge_usb_reset(void)
{
#ifdef CONFIG_TINYUSB_NET_ECM
    if (tud_connected()) {
        ecm_close();
        ecm_open();
    }
#else
    ESP_LOGE(TAG, "You need to reset the USB Nic to get the new IP");
    ESP_LOGE(TAG, "If you want automatic reset, please use USB CDC-ECM");
#endif
    return ESP_OK;
}
```

#### Key Compatibility Points

1. **USB Host vs Device Mode**: The existing implementation is in USB Device mode, while we need USB Host mode to connect to CH397A
2. **Driver Architecture**: Need to implement USB Host driver for ECM devices
3. **Protocol Support**: TinyUSB provides ECM support, but needs Host-side implementation
4. **Integration**: Need to integrate with existing network stack

## Implementation Strategy

### 1. USB Host Driver Layer

#### Required Components

- **USB Host Stack**: ESP-IDF USB Host driver
- **ECM Driver**: USB CDC-ECM host driver
- **Device Management**: Hotplug detection and enumeration

#### Implementation Files

- `bridge_usb_host.c`: USB Host network interface
- `bridge_usb_ecm.c`: ECM protocol handling
- `bridge_router.c`: Intelligent routing engine

### 2. Network Interface Management

#### Dynamic Interface Handling

- **Auto-detection**: Detect CH397A and 4G modules automatically
- **Multi-interface Support**: Manage up to 3 USB network devices
- **Priority Management**: Handle multiple WAN interfaces with priority

#### Routing Modes

1. **4G → WiFi** (4G Router): 4G module as WAN, WiFi SoftAP as LAN
2. **4G → CH397A** (4G Ethernet Adapter): 4G module as WAN, CH397A Ethernet as LAN
3. **WiFi → CH397A** (WiFi Ethernet Adapter): WiFi station as WAN, CH397A Ethernet as LAN
4. **CH397A → WiFi** (Ethernet to WiFi): CH397A connected to upstream router as WAN, WiFi SoftAP as LAN
5. **CH397A → 4G** (Ethernet to 4G): CH397A connected to upstream router as WAN, 4G module as secondary WAN
6. **4G → WiFi + CH397A** (Multi-interface Forwarding): 4G module as WAN, simultaneous forwarding to both WiFi and CH397A
7. **Multi-WAN Load Balancing**: Automatic failover and load balancing between multiple WAN interfaces

### 3. Configuration and Integration

#### Kconfig Extensions

- `CONFIG_BRIDGE_USB_HOST_ENABLE`: Enable USB Host support
- `CONFIG_BRIDGE_USB_HOST_NIC_CH397A`: Support CH397A USB Ethernet
- `CONFIG_BRIDGE_USB_HOST_4G_CAT1`: Support USB 4G CAT1 modem
- `CONFIG_BRIDGE_ROUTING_MODE`: Default routing mode
- `CONFIG_BRIDGE_MULTI_WAN_ENABLE`: Enable multi-WAN support
- `CONFIG_BRIDGE_WAN_PRIORITY_4G`: Priority for 4G WAN (lower number = higher priority)
- `CONFIG_BRIDGE_WAN_PRIORITY_ETH`: Priority for Ethernet WAN
- `CONFIG_BRIDGE_WAN_PRIORITY_WIFI`: Priority for WiFi WAN
- `CONFIG_BRIDGE_AUTO_FAILOVER`: Enable automatic WAN failover
- `CONFIG_BRIDGE_LOAD_BALANCING`: Enable load balancing across WAN interfaces

#### Integration with Existing Components

- **Backward Compatibility**: Maintain compatibility with existing APIs
- **Seamless Transition**: Provide similar interface to existing network APIs
- **Configuration Migration**: Support existing configuration structure

## Code Implementation

### 1. USB Host Initialization

```c
esp_err_t bridge_usb_host_init(void)
{
    ESP_LOGI(TAG, "Initializing USB Host for network devices");
    
    usb_host_config_t host_config = {
        .skip_phy_setup = false,
        .intr_flags = ESP_INTR_FLAG_LEVEL1,
    };
    
    ESP_ERROR_CHECK(usb_host_install(&host_config));
    
    // Initialize USB host task
    xTaskCreatePinnedToCore(usb_host_task, "usb_host", 4096, NULL, 10, NULL, 0);
    
    return ESP_OK;
}
```

### 2. CH397A Device Detection

```c
typedef struct {
    uint16_t vid;
    uint16_t pid;
    const char* name;
    usb_nic_type_t type;
} usb_device_desc_t;

static const usb_device_desc_t supported_devices[] = {
    {0x1A86, 0x7523, "CH397A", USB_NIC_TYPE_ETHERNET},
    {0x2ECC, 0x3012, "4G CAT1", USB_NIC_TYPE_MODEM},
    // Add more devices as needed
};

usb_nic_type_t bridge_usb_host_detect_device(uint16_t vid, uint16_t pid)
{
    for (int i = 0; i < sizeof(supported_devices)/sizeof(supported_devices[0]); i++) {
        if (supported_devices[i].vid == vid && supported_devices[i].pid == pid) {
            return supported_devices[i].type;
        }
    }
    return USB_NIC_TYPE_UNKNOWN;
}
```

### 3. Intelligent Routing Engine

```c
typedef enum {
    ROUTING_MODE_4G_TO_WIFI,       // 4G as WAN, WiFi as LAN
    ROUTING_MODE_4G_TO_ETH,         // 4G as WAN, Ethernet as LAN
    ROUTING_MODE_WIFI_TO_ETH,       // WiFi as WAN, Ethernet as LAN
    ROUTING_MODE_ETH_TO_WIFI,       // Ethernet as WAN, WiFi as LAN
    ROUTING_MODE_ETH_TO_4G,         // Ethernet as WAN, 4G as secondary WAN
    ROUTING_MODE_4G_TO_WIFI_ETH,    // 4G as WAN, both WiFi and Ethernet as LAN
    ROUTING_MODE_MULTI_WAN,         // Multi-WAN load balancing and failover
    ROUTING_MODE_MAX
} routing_mode_t;

esp_err_t bridge_router_set_mode(routing_mode_t mode)
{
    g_router.mode = mode;
    ESP_LOGI(TAG, "Routing mode set to: %d", mode);
    
    // Reconfigure routing tables
    bridge_router_reconfigure();
    
    return ESP_OK;
}
```

## Hardware Configuration

### USB Hub Requirements

- **Power Supply**: Minimum 2A output
- **Ports**: 4-port USB 2.0 hub
- **Compatibility**: Self-powered for stable operation

### ESP32S3 Pin Configuration

| Function | GPIO | Description |
|----------|------|-------------|
| USB_DP   | GPIO20 | USB Data Plus |
| USB_DM   | GPIO19 | USB Data Minus |
| USB_ID   | GPIO18 | USB ID pin (for OTG) |
| VBUS_EN  | GPIO4  | USB VBUS enable |

### CH397A Configuration

- **Driver**: USB CDC-ECM class
- **MAC Address**: Auto-generated or user-configurable
- **Speed**: Auto-negotiation (10/100Mbps)

## Software Configuration

### sdkconfig Settings

```ini
# USB Host Configuration
CONFIG_USB_HOST=y
CONFIG_USB_HOST_TASK_STACK_SIZE=4096

# USB Network Devices
CONFIG_BRIDGE_USB_HOST_ENABLE=y
CONFIG_BRIDGE_USB_HOST_NIC_CH397A=y
CONFIG_BRIDGE_USB_HOST_4G_CAT1=y

# Routing Configuration
CONFIG_BRIDGE_ROUTING_MODE=6
CONFIG_BRIDGE_MULTI_WAN_ENABLE=y
CONFIG_BRIDGE_WAN_PRIORITY_4G=1
CONFIG_BRIDGE_WAN_PRIORITY_ETH=2
CONFIG_BRIDGE_WAN_PRIORITY_WIFI=3

# Disable old SPI Ethernet
CONFIG_ETH_SPI_ETHERNET_W5500=n
```

### Component Dependencies

```yaml
# idf_component.yml
dependencies:
  espressif/iot_bridge:
    version: "^1.1.0"
  espressif/esp_modem:
    version: "^0.10.0"
  espressif/esp_tinyusb:
    version: "^1.1.0"
  espressif/usb_host_cdc_acm:
    version: "^1.0.0"
```

## Migration Steps

### 1. Hardware Setup

1. Connect ESP32S3 to USB Hub
2. Connect CH397A to USB Hub
3. Connect USB 4G CAT1 module to USB Hub
4. Connect STM32F072C8T6 expansion board (if needed)

### 2. Software Installation

1. Update ESP-IDF to version 5.1.4 or higher
2. Add required components
3. Configure sdkconfig settings
4. Build and flash the firmware

### 3. Testing and Validation

1. **Device Detection**: Verify all USB devices are detected
2. **Network Connectivity**: Test each network interface
3. **Routing Modes**: Test all routing configurations
4. **Performance Testing**: Measure throughput and latency
5. **Stability Testing**: Run extended operation tests

## Troubleshooting

### Common Issues

1. **USB Device Not Detected**
   - Check USB Hub power supply
   - Verify USB cables and connections
   - Check USB Host driver initialization

2. **Network Connectivity Issues**
   - Verify IP address configuration
   - Check routing table settings
   - Test cable connections

3. **Performance Problems**
   - Check USB Host stack performance
   - Optimize routing engine
   - Consider USB 3.0 hub for higher throughput

## Performance Considerations

### USB Bandwidth Management

- **Bandwidth Allocation**: Prioritize critical traffic
- **Packet Buffering**: Optimize buffer sizes
- **Interrupt Handling**: Minimize latency

### Power Management

- **USB Power**: Monitor power consumption
- **Sleep Modes**: Implement power-saving strategies
- **Overcurrent Protection**: Ensure hub has proper protection

## Conclusion

This solution provides a flexible, scalable network architecture that leverages USB Host capabilities of ESP32S3 to connect multiple network devices. By supporting CH397A USB Ethernet and USB 4G CAT1 modules, it offers a more versatile alternative to the existing W5500 SPI Ethernet implementation.

The architecture maintains compatibility with existing ESP-IoT-Bridge components while adding support for modern USB network devices, providing better扩展性 and flexibility for future network requirements.
