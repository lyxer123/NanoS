# Patch 目录

[English](README.md) | 中文

本目录用于存放 `managed_components` 的本地补丁。

## 目录约定

- 组件补丁放在 `patch/<component_name>/` 目录下。
- 每个逻辑变更对应一个补丁文件，例如：
  - `patch/espressif__iot_bridge/0001-xxx.patch`
  - `patch/espressif__iot_bridge/0002-yyy.patch`
- 补丁文件名按编号排序，保证应用/回滚顺序可预测。

## 当前状态

- `espressif__iot_bridge`：存在本地补丁。
- 其他 managed 组件：与官方校验和相比无本地差异。
- 差异报告：`patch/component-diff-report.md`

## 各补丁文件作用

`patch/espressif__iot_bridge/0001-fix-windows-idf-path-normalization.patch`

- 主要作用：修复 Windows 下 `patch_utils.cmake` 的 patch 路径替换问题。
- 原因：`%IDF_PATH%` 中的反斜杠在 CMake 正则替换中可能被当作转义，导致构建失败。
- 效果：在替换前将 `IDF_PATH` 规范为 CMake 风格正斜杠，避免 `Unknown escape "\U"` 等错误。

`patch/espressif__iot_bridge/0002-avoid-spi-ethernet-phy-reset-on-dhcp-change.patch`

- 主要作用：避免 SPI Ethernet（W5500）在 DHCP 状态变化时被重置 PHY。
- 原因：WAN 侧 DHCP/DNS 更新可能触发 LAN 侧不必要的 PHY 重置，导致以太网链路断开。
- 效果：当启用 `CONFIG_BRIDGE_USE_SPI_ETHERNET` 时跳过 PHY 重置，保持 W5500 链路稳定。

`patch/espressif__iot_bridge/0003-enhance-bridge-modem-stability-and-registration.patch`

- 主要作用：将 `bridge_modem.c` 的所有本地改动合并到一个补丁文件。
- 原因：同一源码文件的修改集中在同一 patch 中，便于维护、审查和处理冲突。
- 效果：
  - 增加 modem 复位与 USB 就绪等待延时。
  - 为 `esp_modem_get_signal_quality()` 增加 3 次重试逻辑。
  - 在等待到 IP 后通过 `esp_bridge_netif_list_add()` 注册 PPP netif 到 bridge 列表。

## 如何应用补丁

在项目根目录（`NanoS/`）执行：

```bat
patch\apply_patches.bat
```

脚本行为：

- 递归扫描 `patch/**/*.patch`。
- 根据补丁所在父目录推断组件名称。
- 将补丁应用到 `managed_components/<component_name>`。
- 如果补丁已应用则跳过。

退出码：

- `0`：全部成功（已应用或已跳过）
- `1`：环境错误（缺少 git 或 managed_components）
- `2`：一个或多个补丁应用失败

## 如何回滚补丁

在项目根目录（`NanoS/`）执行：

```bat
patch\revert_patches.bat
```

脚本行为：

- 递归扫描 `patch/**/*.patch`。
- 对每个补丁执行 `git apply --reverse` 回滚。
- 如果补丁当前未应用则跳过。

退出码：

- `0`：全部成功（已回滚或已跳过）
- `1`：环境错误
- `2`：一个或多个补丁回滚失败

## 典型流程

1. 拉取或重新生成依赖（`managed_components`）。
2. 执行 `patch\apply_patches.bat`。
3. 编译与测试。
4. 如需恢复官方状态，执行 `patch\revert_patches.bat`。

## 说明

- 脚本依赖 `PATH` 中可用的 `git`。
- 脚本面向 Windows `cmd`。
- 若组件升级后补丁失败，需要基于新上游版本重新生成补丁。
