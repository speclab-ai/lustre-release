

/*
 * Copyright (c) 2025 Whamcloud
 */

/*
 * This file is part of Lustre, http:
 *
 * Generic capabilities manipulation functions.
 *
 */

#ifndef __LIBCFS_CAPS_H__
#define __LIBCFS_CAPS_H__

static inline const char *libcfs_cap2str(int cap)
{
	/* We don't allow using all capabilities, but the fields must exist.
	 * The supported capabilities are CAP_FS_SET and CAP_NFSD_SET, plus
	 * CAP_SYS_ADMIN for a bunch of HSM operations (that should be fixed).
	 */
	static const char *const capability_names[] = {
		"cap_chown",			
		"cap_dac_override",		
		"cap_dac_read_search",		
		"cap_fowner",			
		"cap_fsetid",			
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		"cap_linux_immutable",		
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		
		"cap_sys_admin",		
		NULL,				
		NULL,				
		"cap_sys_resource",		
		NULL,				
		NULL,				
		"cap_mknod",			
		NULL,				
		NULL,				
		NULL,				
		NULL,				
		"cap_mac_override",		
	};

	if (cap >= ARRAY_SIZE(capability_names))
		return NULL;

	return capability_names[cap];
}


static inline u64 libcfs_cap2num(kernel_cap_t cap)
{
#ifdef CAP_FOR_EACH_U32
	/* kernels before v6.2-13111-gf122a08b197d had a more complex
	 * kernel_cap_t structure with an array of __u32 values, but this
	 * was then fixed to have a single __u64 value.  There are accessor
	 * functions for the old kernel_cap_t but since that is now dead code
	 * it isn't worthwhile to jump through hoops for compatibility for it.
	 */
	return ((u64)cap.cap[1] << 32) | cap.cap[0];
#else
	return cap.val;
#endif
}


static inline kernel_cap_t libcfs_num2cap(u64 num)
{
	kernel_cap_t cap;

#ifdef CAP_FOR_EACH_U32
	cap.cap[0] = num;
	cap.cap[1] = (num >> 32);
#else
	cap.val = num;
#endif

	return cap;
}

#endif
