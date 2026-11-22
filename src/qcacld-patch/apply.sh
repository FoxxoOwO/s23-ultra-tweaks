# Apply the S23 compatibility edits to the S24 qcacld copy in /work/b24 (idempotent).
set -e
Q=/work/b24/qcacld-3.0
cp /repo/src/qcacld-patch/s23_cnss_compat.h $Q/core/pld/src/
sed -i "/#include \"s23_cnss_compat.h\"/d" $Q/core/pld/src/pld_pcie.h
sed -i '/case BUS_EVENT_PCI_LINK_RESUME_FAIL:/,+2d' $Q/core/pld/src/pld_pcie.c
sed -i 's/cnss_reason = CNSS_REASON_FW_ASSERTION_FAIL;/cnss_reason = CNSS_REASON_DEFAULT;/' $Q/core/pld/src/pld_pcie.c
grep -q qca_s23_wonder_priv $Q/core/hdd/src/wlan_hdd_wondertap.c || sed -i 's|^#include <wlan_hdd_wondertap.h>|#include <wlan_hdd_wondertap.h>\nconst void *qca_s23_wonder_priv;\nEXPORT_SYMBOL_GPL(qca_s23_wonder_priv);|' $Q/core/hdd/src/wlan_hdd_wondertap.c
grep -n "s23_cnss_compat\|BUS_EVENT_PCI_LINK_RESUME_FAIL\|CNSS_REASON_FW_ASSERTION_FAIL" $Q/core/pld/src/pld_pcie.[ch] | head; grep -n "qca_s23_wonder_priv" $Q/core/hdd/src/wlan_hdd_wondertap.c
# CFI: cnss2 (S23) calls update_status as void (*)(struct pci_dev *, uint32_t); S24 pld uses the enum type.
perl -0pi -e 's/static void pld_pcie_uevent\(struct pci_dev \*pdev,\s*enum cnss_driver_status status\)/static void pld_pcie_uevent(struct pci_dev *pdev, uint32_t status)/' $Q/core/pld/src/pld_pcie.c
grep -n "static void pld_pcie_uevent" $Q/core/pld/src/pld_pcie.c
