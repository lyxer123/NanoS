# Managed Components vs Official Checksum Report

Compared each component under `managed_components/` with its official `CHECKSUMS.json`.

## Components with local differences

### `espressif__iot_bridge`

- `cmake/patch_utils.cmake`
  - local: `dc22621b37288a64acedafca547caca5d118fef0fff2d76e49a2349ef6c6abf6`
  - official: `0b49f1f6d81fd41cbce792e6e503cf9f962fecda1911727b1c3c52d73ccf6a99`
- `src/bridge_eth.c`
  - local: `7d902dfe19ef34a168e6c4c88f8e82e7238b5d0e6dfcedcb0dfc582bead7fc16`
  - official: `a460ad9b2b8b24276b3801f9bdef297074945bf41e2c7f14453cc855696c23fa`

Patch files:
- `patch/espressif__iot_bridge/0001-fix-windows-idf-path-normalization.patch`
- `patch/espressif__iot_bridge/0002-bridge_eth.patch`

## Components without local differences

- `espressif__cmake_utilities`
- `espressif__esp_modem`
- `espressif__esp_modem_usb_dte`
- `espressif__esp_tinyusb`
- `espressif__tinyusb`
- `espressif__usb_host_cdc_acm`
