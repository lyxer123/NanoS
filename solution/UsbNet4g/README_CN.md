# USB 网络桥接解决方案

## 概述

本解决方案提供了一个全面的方法，将现有的 W5500 SPI 以太网迁移到基于 USB 的网络架构，使用 CH397A USB 以太网适配器和 USB 4G CAT1 模块，通过 USB Hub 连接到 ESP32S3。

## 架构分析

### 当前 W5500 实现

- **连接方式**：通过 SPI 接口连接到 ESP32S3
- **角色**：数据转发接口（LAN 端）
- **配置**：DHCP 服务器
- **驱动**：`bridge_eth.c` 中的 SPI 以太网支持

### 新的 USB 架构

```
ESP32S3 (USB OTG Host)
    ↓
USB Hub (4端口)
    ├─→ CH397A USB 以太网 (LAN 接口)
    ├─→ USB 4G CAT1 模块 (WAN 接口)
    ├─→ STM32F072C8T6 扩展板 (功能扩展)
    └─→ (预留端口)
```

## CH397A USB ECM 协议分析

### CH397A 技术特点

- **协议**：USB CDC-ECM (Ethernet Control Model)
- **速度**：10/100Mbps 以太网
- **接口**：USB 2.0 Full Speed
- **兼容性**：标准 USB ECM 类设备

### USB ECM 协议兼容性

#### ESP-IoT-Bridge 中的现有支持

当前的 `bridge_usb.c` 已经包含 ECM 支持：

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

#### 关键兼容性点

1. **USB Host vs Device 模式**：现有实现是 USB Device 模式，而我们需要 USB Host 模式来连接 CH397A
2. **驱动架构**：需要实现 USB Host 端的 ECM 设备驱动
3. **协议支持**：TinyUSB 提供 ECM 支持，但需要 Host 端实现
4. **集成**：需要与现有网络栈集成

## 实现策略

### 1. USB Host 驱动层

#### 所需组件

- **USB Host 栈**：ESP-IDF USB Host 驱动
- **ECM 驱动**：USB CDC-ECM 主机驱动
- **设备管理**：热插拔检测和枚举

#### 实现文件

- `bridge_usb_host.c`：USB Host 网络接口
- `bridge_usb_ecm.c`：ECM 协议处理
- `bridge_router.c`：智能路由引擎

### 2. 网络接口管理

#### 动态接口处理

- **自动检测**：自动检测 CH397A 和 4G 模块
- **多接口支持**：管理最多 3 个 USB 网络设备
- **优先级管理**：处理多个 WAN 接口的优先级

#### 路由模式


```text
┌──────────┐ Downstream  ┌────────────────────────────────┐
|PC/phone  |----─┐       |           [ ESP32S3 ]          |      UP stream
└──────────┘     |       |                                |
                 |       |   ┌──────────┐     ┌────────┐  |                             ┌────────┐
┌─────────────┐  └--->   |   |   SoftAP |     |Station |  |<----------------------------| Router |
| WiFI Device |------>   |   └──────────┘     └────────┘  |                             └────────┘
└─────────────┘          |                                |                                 |
                         |                                |                                 |
┌────────────┐           |                                |                                 |
| BLE Device |------->   |   ┌────────┐     ┌───────┐     |     ┌─────────┐                 |
└────────────┘           |   |   BLE  |     | USB   |     |<----| USB HUB |                 |
                         |   └────────┘     └───────┘     |     └─────────┘                 |
                         |                                |           |                     |
                         |                                |           |                     |
                         └────────────────────────────────┘           |                     |
                                                                      |                     |
                                                       ┌──────────────┴──────────────┐      |
                                                       ▼                             ▼      ▼
                                             ┌─────────────┐             ┌─────────────────────┐
                                             │  4G CAT1    │             │  usb ethernet       │
┌─────────────┐                              └─────────────┘             │                     │
| ETH Device  |--------------------------------------------------------> └─────────────────────┘
└─────────────┘

```

1. **4G对外 → 对内WiFi**（4G 路由器）：4G 模块作为 WAN，WiFi SoftAP 作为 LAN
2. **4G对外 → 对内CH397A**（4G 以太网适配器）：4G 模块作为 WAN，CH397A 以太网作为 LAN
3. **4G对外 → 对内WiFi + CH397A**（多接口转发）：4G 模块作为 WAN，同时转发到 WiFi 和 CH397A
4. **WiFi对外 → 对内CH397A**（WiFi 以太网适配器）：WiFi Station 作为 WAN，CH397A 以太网作为 LAN
5. **CH397A对外 → 对内WiFi**（以太网转 WiFi）：CH397A 连接上级路由器作为 WAN，WiFi SoftAP 作为 LAN
6. **CH397A对外 → 对内4G**（以太网转 4G）：CH397A 连接上级路由器作为 WAN，4G 模块作为备用 WAN
7. **多 WAN 负载均衡**：多个 WAN 接口之间的自动故障转移和负载均衡

### 3. 配置和集成

#### Kconfig 扩展

- `CONFIG_BRIDGE_USB_HOST_ENABLE`：启用 USB Host 支持
- `CONFIG_BRIDGE_USB_HOST_NIC_CH397A`：支持 CH397A USB 以太网
- `CONFIG_BRIDGE_USB_HOST_4G_CAT1`：支持 USB 4G CAT1  modem
- `CONFIG_BRIDGE_ROUTING_MODE`：默认路由模式
- `CONFIG_BRIDGE_MULTI_WAN_ENABLE`：启用多 WAN 支持
- `CONFIG_BRIDGE_WAN_PRIORITY_4G`：4G WAN 的优先级（数字越小优先级越高）
- `CONFIG_BRIDGE_WAN_PRIORITY_ETH`：以太网 WAN 的优先级
- `CONFIG_BRIDGE_WAN_PRIORITY_WIFI`：WiFi WAN 的优先级
- `CONFIG_BRIDGE_AUTO_FAILOVER`：启用自动 WAN 故障转移
- `CONFIG_BRIDGE_LOAD_BALANCING`：启用跨 WAN 接口的负载均衡

#### 与现有组件集成

- **向后兼容**：保持与现有 API 的兼容性
- **无缝过渡**：提供与现有网络 API 类似的接口
- **配置迁移**：支持现有的配置结构

## 代码实现

### 1. USB Host 初始化

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

### 2. CH397A 设备检测

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

### 3. 智能路由引擎

```c
typedef enum {
    ROUTING_MODE_4G_TO_WIFI,       // 4G 作为 WAN，WiFi 作为 LAN
    ROUTING_MODE_4G_TO_ETH,         // 4G 作为 WAN，以太网作为 LAN
    ROUTING_MODE_WIFI_TO_ETH,       // WiFi 作为 WAN，以太网作为 LAN
    ROUTING_MODE_ETH_TO_WIFI,       // 以太网作为 WAN，WiFi 作为 LAN
    ROUTING_MODE_ETH_TO_4G,         // 以太网作为 WAN，4G 作为备用 WAN
    ROUTING_MODE_4G_TO_WIFI_ETH,    // 4G 作为 WAN，同时 WiFi 和以太网作为 LAN
    ROUTING_MODE_MULTI_WAN,         // 多 WAN 负载均衡和故障转移
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

## 硬件配置

### USB Hub 要求

- **电源供应**：最小 2A 输出
- **端口**：4 端口 USB 2.0  hub
- **兼容性**：自供电以确保稳定运行

### ESP32S3 引脚配置

| 功能 | GPIO | 描述 |
|------|------|------|
| USB_DP | GPIO20 | USB 数据正 |
| USB_DM | GPIO19 | USB 数据负 |
| USB_ID | GPIO18 | USB ID 引脚（用于 OTG） |
| VBUS_EN | GPIO4 | USB VBUS 使能 |

### CH397A 配置

- **驱动**：USB CDC-ECM 类
- **MAC 地址**：自动生成或用户可配置
- **速度**：自动协商（10/100Mbps）

## 软件配置

### sdkconfig 设置

```ini
# USB Host 配置
CONFIG_USB_HOST=y
CONFIG_USB_HOST_TASK_STACK_SIZE=4096

# USB 网络设备
CONFIG_BRIDGE_USB_HOST_ENABLE=y
CONFIG_BRIDGE_USB_HOST_NIC_CH397A=y
CONFIG_BRIDGE_USB_HOST_4G_CAT1=y

# 路由配置
CONFIG_BRIDGE_ROUTING_MODE=6
CONFIG_BRIDGE_MULTI_WAN_ENABLE=y
CONFIG_BRIDGE_WAN_PRIORITY_4G=1
CONFIG_BRIDGE_WAN_PRIORITY_ETH=2
CONFIG_BRIDGE_WAN_PRIORITY_WIFI=3

# 禁用旧的 SPI 以太网
CONFIG_ETH_SPI_ETHERNET_W5500=n
```

### 组件依赖

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

## 迁移步骤

### 1. 硬件设置

1. 将 ESP32S3 连接到 USB Hub
2. 将 CH397A 连接到 USB Hub
3. 将 USB 4G CAT1 模块连接到 USB Hub
4. 连接 STM32F072C8T6 扩展板（如果需要）

### 2. 软件安装

1. 将 ESP-IDF 更新到 5.1.4 或更高版本
2. 添加所需组件
3. 配置 sdkconfig 设置
4. 构建并烧录固件

### 3. 测试和验证

1. **设备检测**：验证所有 USB 设备是否被检测到
2. **网络连接**：测试每个网络接口
3. **路由模式**：测试所有路由配置
4. **性能测试**：测量吞吐量和延迟
5. **稳定性测试**：运行扩展操作测试

## 故障排除

### 常见问题

1. **USB 设备未检测到**
   - 检查 USB Hub 电源供应
   - 验证 USB 电缆和连接
   - 检查 USB Host 驱动初始化

2. **网络连接问题**
   - 验证 IP 地址配置
   - 检查路由表设置
   - 测试电缆连接

3. **性能问题**
   - 检查 USB Host 栈性能
   - 优化路由引擎
   - 考虑使用 USB 3.0 hub 以获得更高的吞吐量

## 性能考虑

### USB 带宽管理

- **带宽分配**：优先处理关键流量
- **数据包缓冲**：优化缓冲区大小
- **中断处理**：最小化延迟

### 电源管理

- **USB 电源**：监控功耗
- **睡眠模式**：实现节能策略
- **过流保护**：确保 hub 有适当的保护

## 结论

本解决方案提供了一个灵活、可扩展的网络架构，利用 ESP32S3 的 USB Host 功能连接多个网络设备。通过支持 CH397A USB 以太网和 USB 4G CAT1 模块，它提供了比现有 W5500 SPI 以太网实现更通用的替代方案。

该架构在保持与现有 ESP-IoT-Bridge 组件兼容性的同时，增加了对现代 USB 网络设备的支持，为未来的网络需求提供了更好的扩展性和灵活性。
