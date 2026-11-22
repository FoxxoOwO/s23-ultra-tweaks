/* S23 (kalama, older cnss2) compatibility for the S24 qcacld-3.0: newer cnss2 APIs the S23
 * platform driver does not export are stubbed; the Wonder priv-data hand-off goes through an
 * exported pointer instead of the S24 cnss2 "vendor-wlan-wonder" component device. */
#ifndef S23_CNSS_COMPAT_H
#define S23_CNSS_COMPAT_H
#include <linux/errno.h>
#include <linux/types.h>
struct device;
extern const void *qca_s23_wonder_priv;
static inline int cnss_update_time_sync_period(struct device *dev, uint32_t p) { return -EOPNOTSUPP; }
static inline int cnss_reset_time_sync_period(struct device *dev) { return -EOPNOTSUPP; }
static inline int cnss_pci_get_iova_info(struct device *dev, u64 *addr, u64 *size) { return -EINVAL; }
static inline int cnss_get_fw_lpass_shared_mem(struct device *dev, dma_addr_t *iova, size_t *size) { return -EINVAL; }
static inline bool cnss_ipa_wlan_shared_smmu_supported(struct device *dev) { return false; }
static inline bool cnss_get_audio_shared_iommu_group_cap(struct device *dev) { return false; }
static inline bool cnss_audio_is_direct_link_supported(struct device *dev) { return false; }
static inline int cnss_sysfs_get_pwr_mode_for_rftestmode(void) { return 0; }
static inline int cnss_set_vendor_wonder_priv_data(const void *priv) { qca_s23_wonder_priv = priv; return 0; }
#endif
