// SPDX-License-Identifier: GPL-2.0
/*
 * One-shot helper for the S23 Wi-Fi (kiwi, PCI 17cb:1107) before swapping in a different
 * firmware at runtime. cnss2/MHI keep buffers sized for the boot-time firmware:
 *  - MHI BHIe tables (img_pre_alloc): a larger amss20.bin overruns them -> panic in memcpy.
 *  - cnss2 fw_mem type 1 (DDR): the QMI handler updates .size but keeps the old buffer,
 *    so the firmware is told it has more memory than is mapped -> SMMU fault.
 * mode=0 (default): report only.  mode=1: free both, only while the MHI controller is
 * MHI_PM_DISABLE (Wi-Fi driver unloaded, chip off) and only if every check passed.
 * Loading always ends with -EAGAIN after doing its work, so nothing stays resident.
 *
 * MHI offsets: phone BTF (/sys/kernel/btf/mhi), S918WVLU8GZIF. cnss_fw_mem layout: S23
 * cnss2/main.h; its position in cnss_plat_data is found by signature, not assumed.
 * plat_env= is the address of cnss2's 'plat_env' pointer from /proc/kallsyms.
 */
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/device.h>
#include <linux/dma-mapping.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/uaccess.h>

#define OFF_MHIDEV_CNTRL   16   /* struct mhi_device.mhi_cntrl */
#define OFF_MHIDEV_DEV     40   /* struct mhi_device.dev */
#define OFF_C_CNTRL_DEV     0   /* struct mhi_controller.cntrl_dev */
#define OFF_C_MHI_DEV       8   /* .mhi_dev */
#define OFF_C_RDDM_SIZE    96
#define OFF_C_SBL_SIZE    104
#define OFF_C_SEG_LEN     112
#define OFF_C_FBC_IMAGE   128
#define OFF_C_RDDM_IMAGE  136
#define OFF_C_PM_STATE    384
#define OFF_C_PRE_ALLOC   652   /* bool img_pre_alloc */
#define OFF_C_FBC_DL      654   /* bool fbc_download */
#define MHI_PM_DISABLE    0x1

struct s23_mhi_buf { void *buf; char *name; dma_addr_t dma_addr; size_t len; };   /* 32 bytes */
struct s23_image_info { struct s23_mhi_buf *mhi_buf; void *bhi_vec; u32 entries; }; /* 24 bytes */
/* cnss2/main.h struct cnss_fw_mem, 40 bytes */
struct s23_fw_mem { size_t size; void *va; phys_addr_t pa; u8 valid; u32 type; unsigned long attrs; };
#define FW_TYPE_DDR       1
#define FW_TYPE_4         4
#define FW_TYPE4_SIZE     0x810000
#define NEW_FW_DDR_SIZE   0x730000      /* what the S24 firmware asks for */
#define SCAN_MAX          65536

static int mode;
module_param(mode, int, 0444);
static unsigned long plat_env;
module_param(plat_env, ulong, 0444);
static unsigned long fw_alloc_size = 0x6c0000;  /* size the boot-time (S23) firmware allocated */
module_param(fw_alloc_size, ulong, 0444);

#define F(c, off, t) (*(t *)((char *)(c) + (off)))

static int match_mhi(struct device *dev, void *data)
{
	return !strncmp(dev_name(dev), "mhi_1107", 8);
}

static size_t table_bytes(struct s23_image_info *ii)
{
	size_t s = 0; u32 i;

	if (!ii)
		return 0;
	for (i = 0; i + 1 < ii->entries; i++)   /* last entry is the vector table */
		s += ii->mhi_buf[i].len;
	return s;
}

static void free_table(void *c, struct s23_image_info **pii)
{
	struct device *cdev = F(c, OFF_C_CNTRL_DEV, struct device *);
	struct s23_image_info *ii = *pii;
	u32 i;

	if (!ii)
		return;
	for (i = 0; i < ii->entries; i++)
		dma_free_attrs(cdev, ii->mhi_buf[i].len, ii->mhi_buf[i].buf,
			       ii->mhi_buf[i].dma_addr, DMA_ATTR_FORCE_CONTIGUOUS);
	kfree(ii->mhi_buf);
	kfree(ii);
	*pii = NULL;
}

/* Find the fw_mem[] array inside cnss_plat_data: exactly one place where entry 0 is the
 * DDR buffer and entry 1 the type-4 buffer of the known size. Returns offset or <0. */
static long find_fw_mem(void *pp, struct s23_fw_mem *e0)
{
	struct s23_fw_mem e[2];
	long off, hit = -1;
	int n = 0;

	for (off = 0; off + (long)sizeof(e) <= SCAN_MAX; off += 8) {
		if (copy_from_kernel_nofault(e, (char *)pp + off, sizeof(e)))
			break;
		if (e[0].type == FW_TYPE_DDR && e[0].va && e[0].pa && !(e[0].pa & 0xffff) &&
		    (e[0].size == fw_alloc_size || e[0].size == NEW_FW_DDR_SIZE) &&
		    e[1].type == FW_TYPE_4 && e[1].size == FW_TYPE4_SIZE && e[1].va) {
			hit = off; *e0 = e[0]; n++;
		}
	}
	return n == 1 ? hit : (n ? -2 : -1);
}

static int __init mhifix_init(void)
{
	struct pci_dev *pdev;
	struct device *child;
	void *mdev, *c, *pp = NULL;
	struct s23_image_info **fbc, **rddm;
	struct s23_fw_mem e0 = {};
	long fw_off = -1;
	int ret = -EAGAIN;

	pdev = pci_get_device(0x17cb, 0x1107, NULL);
	if (!pdev) {
		pr_err("mhifix: no 17cb:1107 PCI device\n");
		return -ENODEV;
	}
	child = device_find_child(&pdev->dev, NULL, match_mhi);
	if (!child) {
		pr_err("mhifix: no mhi_1107 child device\n");
		pci_dev_put(pdev);
		return -ENODEV;
	}
	mdev = (char *)child - OFF_MHIDEV_DEV;
	c = F(mdev, OFF_MHIDEV_CNTRL, void *);
	if (!c || F(c, OFF_C_MHI_DEV, void *) != mdev || F(c, OFF_C_CNTRL_DEV, struct device *) != &pdev->dev) {
		pr_err("mhifix: layout check failed (cntrl=%px), doing nothing\n", c);
		ret = -EINVAL;
		goto out;
	}
	fbc = &F(c, OFF_C_FBC_IMAGE, struct s23_image_info *);
	rddm = &F(c, OFF_C_RDDM_IMAGE, struct s23_image_info *);
	pr_info("mhifix: pm_state=%#x pre_alloc=%d fbc_dl=%d seg_len=%zu sbl=%zu rddm_size=%zu fbc=%zu bytes/%u rddm=%zu bytes/%u\n",
		F(c, OFF_C_PM_STATE, u32), F(c, OFF_C_PRE_ALLOC, bool), F(c, OFF_C_FBC_DL, bool),
		F(c, OFF_C_SEG_LEN, size_t), F(c, OFF_C_SBL_SIZE, size_t), F(c, OFF_C_RDDM_SIZE, size_t),
		table_bytes(*fbc), *fbc ? (*fbc)->entries : 0, table_bytes(*rddm), *rddm ? (*rddm)->entries : 0);

	if (plat_env) {
		if (copy_from_kernel_nofault(&pp, (void *)plat_env, sizeof(pp)) || !pp) {
			pr_err("mhifix: cannot read plat_env at %lx\n", plat_env);
			ret = -EINVAL;
			goto out;
		}
		fw_off = find_fw_mem(pp, &e0);
		if (fw_off < 0)
			pr_err("mhifix: fw_mem signature %s (plat_priv %px)\n",
			       fw_off == -2 ? "ambiguous" : "not found", pp);
		else
			pr_info("mhifix: fw_mem[DDR] at plat_priv+%ld size=%#zx alloc=%#lx pa=%pa attrs=%#lx\n",
				fw_off, e0.size, fw_alloc_size, &e0.pa, e0.attrs);
	}

	if (mode != 1)
		goto out;
	if (F(c, OFF_C_PM_STATE, u32) != MHI_PM_DISABLE) {
		pr_err("mhifix: MHI not powered off, refusing\n");
		ret = -EBUSY;
		goto out;
	}
	if (plat_env && fw_off < 0) {
		pr_err("mhifix: fw_mem not located, refusing (nothing changed)\n");
		ret = -EINVAL;
		goto out;
	}
	F(c, OFF_C_PRE_ALLOC, bool) = false;
	free_table(c, fbc);
	free_table(c, rddm);
	pr_info("mhifix: tables freed, img_pre_alloc cleared; next power-up reallocates\n");
	if (plat_env) {
		struct s23_fw_mem *t = (struct s23_fw_mem *)((char *)pp + fw_off);

		dma_free_attrs(&pdev->dev, fw_alloc_size, e0.va, e0.pa, e0.attrs);
		t->va = NULL;
		t->pa = 0;
		pr_info("mhifix: fw_mem DDR freed; next FW start reallocates at the requested size\n");
	}
out:
	put_device(child);
	pci_dev_put(pdev);
	return ret;
}

module_init(mhifix_init);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("S23 kiwi: drop pinned MHI tables and cnss2 FW DDR memory before a firmware swap");
