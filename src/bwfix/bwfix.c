// SPDX-License-Identifier: GPL-2.0
/*
 * S23 kiwi (PCI 17cb:1107) running the S24 firmware: when the AirDrop (Wondertap passthru)
 * vdev starts, the firmware sends an MHI bandwidth-scale request for PCIe Gen3. The S23 root
 * port's bw-scale table stops at Gen2, so cnss2's callback fails with -EINVAL, MHI NACKs, and
 * the firmware asserts in mhi_core_process_bandwidth_change (cmnos_thread_patch.c:1269).
 *
 * This replaces the controller's bw-scale callback with one that clamps the requested speed
 * to max_speed (default Gen2, what the S23 link supports), applies it with
 * msm_pcie_set_link_bandwidth() and ACKs. The link never goes faster than the hardware allows.
 *
 * orig= is the address of cnss2's "cnss_mhi_bw_scale.cfi_jt" from /proc/kallsyms. With it,
 * rmmod puts cnss2's callback back; without it the module pins itself (unload = reboot).
 */
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/device.h>
#include <linux/string.h>
#include <linux/mhi.h>
#include <linux/mhi_misc.h>
#include <linux/msm_pcie.h>

static uint max_speed = 2;
module_param(max_speed, uint, 0444);
static unsigned long orig;
module_param(orig, ulong, 0444);

typedef int (*bw_cb_t)(struct mhi_controller *, struct mhi_link_info *);
static struct mhi_controller *bw_cntrl;
static struct pci_dev *bw_pdev;
static atomic_t n_req = ATOMIC_INIT(0);

static int bwfix_bw_scale(struct mhi_controller *mhi_cntrl, struct mhi_link_info *li)
{
	u32 req = li->target_link_speed, sp = min_t(u32, req, max_speed);
	int ret = msm_pcie_set_link_bandwidth(bw_pdev, sp, li->target_link_width);

	pr_info("bwfix: #%d firmware asked gen%u x%u (seq %u); set gen%u: %d; ACK\n",
		atomic_inc_return(&n_req), req, li->target_link_width, li->sequence_num, sp, ret);
	li->target_link_speed = sp;	/* MHI records this as the current link */
	return 0;
}

static int match_mhi(struct device *dev, void *data)
{
	return !strncmp(dev_name(dev), "mhi_1107", 8);
}

static int __init bwfix_init(void)
{
	struct device *child;
	struct mhi_device *mdev;

	/* struct layout must match the phone's BTF (see mhifix.c) */
	BUILD_BUG_ON(offsetof(struct mhi_device, mhi_cntrl) != 16);
	BUILD_BUG_ON(offsetof(struct mhi_device, dev) != 40);
	BUILD_BUG_ON(offsetof(struct mhi_controller, cntrl_dev) != 0);
	BUILD_BUG_ON(offsetof(struct mhi_controller, mhi_dev) != 8);
	BUILD_BUG_ON(sizeof(struct mhi_link_info) != 12);

	bw_pdev = pci_get_device(0x17cb, 0x1107, NULL);
	if (!bw_pdev)
		return -ENODEV;
	child = device_find_child(&bw_pdev->dev, NULL, match_mhi);
	if (!child) {
		pci_dev_put(bw_pdev);
		return -ENODEV;
	}
	mdev = container_of(child, struct mhi_device, dev);
	bw_cntrl = mdev->mhi_cntrl;
	put_device(child);
	if (!bw_cntrl || bw_cntrl->mhi_dev != mdev || bw_cntrl->cntrl_dev != &bw_pdev->dev) {
		pr_err("bwfix: controller check failed, doing nothing\n");
		pci_dev_put(bw_pdev);
		return -EINVAL;
	}
	mhi_controller_set_bw_scale_cb(bw_cntrl, bwfix_bw_scale);
	if (!orig)
		__module_get(THIS_MODULE);
	pr_info("bwfix: bw-scale callback replaced (clamp to gen%u)%s\n", max_speed,
		orig ? "" : "; pinned, no orig= given");
	return 0;
}

static void __exit bwfix_exit(void)
{
	mhi_controller_set_bw_scale_cb(bw_cntrl, (bw_cb_t)orig);
	pci_dev_put(bw_pdev);
	pr_info("bwfix: cnss2 bw-scale callback restored\n");
}

module_init(bwfix_init);
module_exit(bwfix_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("S23 kiwi + S24 firmware: clamp and ACK MHI PCIe bandwidth-scale requests");
