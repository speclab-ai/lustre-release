



/* This file is part of Lustre, http:
 *
 * Author: Nic Henke <nic@cray.com>
 * Author: James Shimek <jshimek@cray.com>
 */

#ifndef _GNILND_GEMINI_H
#define _GNILND_GEMINI_H

#ifndef _GNILND_HSS_OPS_H
# error "must include gnilnd_hss_ops.h first"
#endif


#define GNILND_BASE_TIMEOUT        60            
#define GNILND_CHECKSUM_DEFAULT     3            

#define GNILND_REVERSE_RDMA	    GNILND_REVERSE_NONE
#define GNILND_RDMA_DLVR_OPTION     GNI_DLVMODE_PERFORMANCE

#if !defined(CONFIG_CRAY_COMPUTE)
#define GNILND_SCHED_THREADS        3            
#endif


#define GNILND_KGNI_TS_MINOR_VER 0x44
#define GNILND_TS_ENABLE         0

static inline gni_return_t
kgnilnd_register_smdd_buf(kgn_device_t *dev)
{
	return GNI_RC_SUCCESS;
}

static inline gni_return_t
kgnilnd_deregister_smdd_buf(kgn_device_t *dev)
{
	return GNI_RC_SUCCESS;
}

#endif 
