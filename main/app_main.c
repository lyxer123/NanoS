/*
 * NanoS network bootstrap based on esp-iot-bridge 4g_nic example.
 */

#include "nvs_flash.h"
#include "esp_err.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_bridge.h"

static void storage_init(void)
{
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);
}

void app_main(void)
{
    storage_init();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());

    // Create bridge netifs based on menuconfig/sdkconfig selections.
    esp_bridge_create_all_netif();
}
