# Patch Directory

English | [中文](readmeCN.md)

This directory stores local patches for `managed_components`.

## Directory convention

- Put component patches under `patch/<component_name>/`.
- One patch file per logical change, for example:
  - `patch/espressif__iot_bridge/0001-xxx.patch`
  - `patch/espressif__iot_bridge/0002-yyy.patch`
- Keep patch filenames ordered by number so apply/revert order is deterministic.

## Current status

- `espressif__iot_bridge`: local patches exist.
- Other managed components: no local differences against official checksums.
- Detailed report: `patch/component-diff-report.md`

## Patch purpose by file

`patch/espressif__iot_bridge/0001-fix-windows-idf-path-normalization.patch`

- Main role: Fix patch path replacement on Windows in `patch_utils.cmake`.
- Why needed: Backslashes in `%IDF_PATH%` can be interpreted as escape sequences by CMake regex replacement and break builds.
- Effect: Converts `IDF_PATH` to CMake-style forward slashes before replacement, preventing `Unknown escape "\U"` type errors.

`patch/espressif__iot_bridge/0002-bridge_eth.patch`

- Main role: Single patch for **`src/bridge_eth.c`** (all local edits to that file merged together).
- Contents:
  - SPI Ethernet (W5500): skip PHY reset in `eth_netif_dhcp_status_change_cb` on WAN DHCP/DNS churn so LAN link stays up.
  - `esp_bridge_create_eth_netif`: comment before `esp_netif_up` noting that **`esp_eth_start` already runs `esp_netif_action_start` / `netif_add` via glue** and must not be duplicated (otherwise lwIP asserts `netif already added`).

`patch/espressif__iot_bridge/0003-enhance-bridge-modem-stability-and-registration.patch`

- Main role: Consolidate all local `bridge_modem.c` changes into one patch file.
- Why needed: Keep modifications to the same source file in a single patch for easier maintenance, review, and conflict handling.
- Effect:
  - Increases modem reset and USB-ready wait delays.
  - Adds retry logic (3 attempts) for `esp_modem_get_signal_quality()`.
  - Registers PPP netif into bridge list via `esp_bridge_netif_list_add()` after IP wait.

## How to apply patches

From project root (`NanoS/`):

```bat
patch\apply_patches.bat
```

What it does:

- Recursively scans `patch/**/*.patch`.
- Infers component name from patch parent folder.
- Applies patch into `managed_components/<component_name>`.
- Skips patch if already applied.

Exit code:

- `0`: all good (applied or skipped)
- `1`: environment error (missing git or managed_components)
- `2`: one or more patches failed

## How to revert patches

From project root (`NanoS/`):

```bat
patch\revert_patches.bat
```

What it does:

- Recursively scans `patch/**/*.patch`.
- Reverts each patch with `git apply --reverse`.
- Skips patch if not currently applied.

Exit code:

- `0`: all good (reverted or skipped)
- `1`: environment error
- `2`: one or more reverts failed

## Typical workflow

1. Pull or regenerate dependencies (`managed_components`).
2. Run `patch\apply_patches.bat`.
3. Build and test.
4. If needed, restore official state with `patch\revert_patches.bat`.

## Notes

- Scripts require `git` in `PATH`.
- Scripts are designed for Windows `cmd`.
- If a patch fails after component upgrade, regenerate the patch for the new upstream version.
