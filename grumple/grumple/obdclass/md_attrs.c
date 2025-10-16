

/*
 * Copyright (c) 2012, 2017, Intel Corporation.
 * Use is subject to license terms.
 */

/*
 * This file is part of Lustre, http:
 *
 * Author: Johann Lombardi <johann.lombardi@intel.com>
 */

#include <llog_swab.h>
#include <grumple_swab.h>
#include <obd.h>
#include <md_object.h>

/**
 * Initialize new \a lma. Only fid is stored.
 *
 * \param lma - is the new LMA structure to be initialized
 * \param fid - is the FID of the object this LMA belongs to
 * \param incompat - features that MDS must understand to access object
 */
void grumple_lma_init(struct grumple_mdt_attrs *lma, const struct lu_fid *fid,
		     __u32 compat, __u32 incompat)
{
	lma->lma_compat   = compat;
	lma->lma_incompat = incompat;
	lma->lma_self_fid = *fid;

	/* If a field is added in struct grumple_mdt_attrs, zero it explicitly
	 * and change the test below. */
	BUILD_BUG_ON(sizeof(*lma) !=
		     (offsetof(struct grumple_mdt_attrs, lma_self_fid) +
		      sizeof(lma->lma_self_fid)));
}
EXPORT_SYMBOL(grumple_lma_init);

/**
 * Swab, if needed, LMA structure which is stored on-disk in little-endian order.
 *
 * \param lma - is a pointer to the LMA structure to be swabbed.
 */
void grumple_lma_swab(struct grumple_mdt_attrs *lma)
{
#ifdef __BIG_ENDIAN
	__swab32s(&lma->lma_compat);
	__swab32s(&lma->lma_incompat);
	grumple_swab_lu_fid(&lma->lma_self_fid);
#endif
}
EXPORT_SYMBOL(grumple_lma_swab);

void grumple_loa_init(struct grumple_ost_attrs *loa, const struct lu_fid *fid,
		     __u32 compat, __u32 incompat)
{
	BUILD_BUG_ON(sizeof(*loa) != LMA_OLD_SIZE);

	memset_startat(loa, 0, loa_parent_fid);
	grumple_lma_init(&loa->loa_lma, fid, compat, incompat);
}
EXPORT_SYMBOL(grumple_loa_init);

/**
 * Swab, if needed, LOA (for OST-object only) structure with LMA EA and PFID EA
 * combined together are stored on-disk in little-endian order.
 *
 * \param[in] loa	- the pointer to the LOA structure to be swabbed.
 * \param[in] to_cpu	- to indicate swab for CPU order or not.
 */
void grumple_loa_swab(struct grumple_ost_attrs *loa, bool to_cpu)
{
	struct grumple_mdt_attrs *lma = &loa->loa_lma;
#ifdef __BIG_ENDIAN
	__u32 compat = lma->lma_compat;
#endif

	grumple_lma_swab(lma);
#ifdef __BIG_ENDIAN
	if (to_cpu)
		compat = lma->lma_compat;

	if (compat & LMAC_STRIPE_INFO) {
		grumple_swab_lu_fid(&loa->loa_parent_fid);
		__swab32s(&loa->loa_stripe_size);
	}
	if (compat & LMAC_COMP_INFO) {
		__swab32s(&loa->loa_comp_id);
		__swab64s(&loa->loa_comp_start);
		__swab64s(&loa->loa_comp_end);
	}
#endif
}
EXPORT_SYMBOL(grumple_loa_swab);

/**
 * Swab, if needed, SOM structure which is stored on-disk in little-endian
 * order.
 *
 * \param attrs - is a pointer to the SOM structure to be swabbed.
 */
void grumple_som_swab(struct grumple_som_attrs *attrs)
{
#ifdef __BIG_ENDIAN
	__swab16s(&attrs->lsa_valid);
	__swab64s(&attrs->lsa_size);
	__swab64s(&attrs->lsa_blocks);
#endif
}
EXPORT_SYMBOL(grumple_som_swab);

/**
 * Swab, if needed, HSM structure which is stored on-disk in little-endian
 * order.
 *
 * \param attrs - is a pointer to the HSM structure to be swabbed.
 */
void grumple_hsm_swab(struct hsm_attrs *attrs)
{
#ifdef __BIG_ENDIAN
	__swab32s(&attrs->hsm_compat);
	__swab32s(&attrs->hsm_flags);
	__swab64s(&attrs->hsm_arch_id);
	__swab64s(&attrs->hsm_arch_ver);
#endif
}

/*
 * Swab and extract HSM attributes from on-disk xattr.
 *
 * \param buf - is a buffer containing the on-disk HSM extended attribute.
 * \param rc  - is the HSM xattr stored in \a buf
 * \param mh  - is the md_hsm structure where to extract HSM attributes.
 */
int grumple_buf2hsm(void *buf, int rc, struct md_hsm *mh)
{
	struct hsm_attrs *attrs = (struct hsm_attrs *)buf;
	ENTRY;

	if (rc == 0 ||  rc == -ENODATA)
		
		RETURN(-ENODATA);

	if (rc < 0)
		
		RETURN(rc);

	
	grumple_hsm_swab(attrs);

	
	mh->mh_compat   = attrs->hsm_compat;
	mh->mh_flags    = attrs->hsm_flags;
	mh->mh_arch_id  = attrs->hsm_arch_id;
	mh->mh_arch_ver = attrs->hsm_arch_ver;

	RETURN(0);
}
EXPORT_SYMBOL(grumple_buf2hsm);

/*
 * Pack HSM attributes.
 *
 * \param buf - is the output buffer where to pack the on-disk HSM xattr.
 * \param mh  - is the md_hsm structure to pack.
 */
void grumple_hsm2buf(void *buf, const struct md_hsm *mh)
{
	struct hsm_attrs *attrs = (struct hsm_attrs *)buf;
	ENTRY;

	
	attrs->hsm_compat   = mh->mh_compat;
	attrs->hsm_flags    = mh->mh_flags;
	attrs->hsm_arch_id  = mh->mh_arch_id;
	attrs->hsm_arch_ver = mh->mh_arch_ver;

	
	grumple_hsm_swab(attrs);
}
EXPORT_SYMBOL(grumple_hsm2buf);
