/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Google Wonder WiFi Virtual Soft-MAC Driver
 *
 * Main entry point for the Wonder driver module. This file handles the
 * initialization and cleanup of the driver, locating the physical
 * network device and kicking off the mac80211 registration process.
 */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/version.h>
#include <linux/init.h>
#include <linux/netdevice.h>
#include <linux/platform_device.h>
#include <linux/component.h>
#include <linux/of.h>
#include <linux/of_platform.h>

#include "core.h"
#include "mac80211.h"
#include "wonder_log.h"
#include "include/wonder/wondertap.h"
#include "wondertap_internal.h"


/* Module parameter for setting the physical device name */
module_param(physical_name, charp, 0444);
MODULE_PARM_DESC(physical_name, "Interface name to use (e.g., wlan0, radiotap0, ...)");


#define WONDER_MAX_COMPAT_VERSIONS 6
static int wonder_ver_match_table[WONDER_MAX_COMPAT_VERSIONS] = {
	WONDER_VERSION_1_6_4,
	WONDER_VERSION_1_6_3,
	WONDER_VERSION_1_4,
	WONDER_VERSION_1_6_5,
	WONDER_VERSION_1_5,
	-1,
};

static bool wonder_ver_can_support(enum wondertap_ver slave, enum wondertap_ver master)
{
	int i;

	if (slave < 0 || slave >= WONDER_VERSION_MAX)
		return false;

	for (i = 0; i < WONDER_MAX_COMPAT_VERSIONS; i++) {
		if (wonder_ver_match_table[i] == -1)
			break;
		if (wonder_ver_match_table[i] == slave)
			return true;
	}
	return false;
}

/*
 * S23 port: the S23 (kalama) cnss2 has no "vendor-wlan-wonder" component device and the S23
 * device tree has no "google,wonder-drv-v1" node, so instead of a DT-matched platform driver
 * this module binds directly to the Wondertap provider published by the patched
 * qca_cld3_kiwi_v2 through the exported qca_s23_wonder_priv pointer. Load it after the
 * Wi-Fi driver has probed.
 */
extern const void *qca_s23_wonder_priv;
static struct wonder_data *s23_wonder;

static int __init wonder_s23_init(void)
{
	const struct wondertap_priv *wlan_priv = qca_s23_wonder_priv;
	struct wondertap_data *wondertap;
	int ret;

	if (!wlan_priv || !wlan_priv->wonder_ops) {
		pr_err("wonder: Wondertap provider not registered (is the patched Wi-Fi driver up?)\n");
		return -ENODEV;
	}
	s23_wonder = wonder_mac80211_init();
	if (!s23_wonder)
		return -ENODEV;
	wondertap = &s23_wonder->wondertap_data;
	wondertap->ver = WONDER_VERSION_1_6_5;
	if (!wonder_ver_can_support(wlan_priv->ver, wondertap->ver)) {
		pr_err("wonder: wondertap interface version mismatch(%d,%d)\n", wlan_priv->ver, wondertap->ver);
		ret = -EINVAL;
		goto err;
	}
	wondertap_register_ops(wlan_priv->wonder_ops);
	wondertap->wonder_ops = wlan_priv->wonder_ops;
	wondertap->wifi_ver = wlan_priv->ver;
	pr_info("wonder: connected to wlan ver %d (wonder ver %d)\n", wlan_priv->ver, wondertap->ver);
	ret = wondertap_get_capabilities(wondertap, &wondertap->cap);
	if (ret) {
		pr_err("wonder: failed to get wondertap capabilities: %d\n", ret);
		wondertap_unregister_ops(wondertap->wonder_ops);
		goto err;
	}
	return wonder_debugfs_init(s23_wonder);
err:
	wonder_mac80211_exit();
	s23_wonder = NULL;
	return ret;
}

static void __exit wonder_s23_exit(void)
{
	if (!s23_wonder)
		return;
	wondertap_unregister_ops(s23_wonder->wondertap_data.wonder_ops);
	wonder_debugfs_exit();
	wonder_mac80211_exit();
}
module_init(wonder_s23_init);
module_exit(wonder_s23_exit);

MODULE_DESCRIPTION("Google Wonder Virtual mac80211 Driver");
MODULE_LICENSE("GPL");
MODULE_AUTHOR("Google Android WiFi Team");
