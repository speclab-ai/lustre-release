

/*
 * Copyright (c) 2008, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2014, 2017, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 */

#ifndef _GRUMPLE_ACL_H
#define _GRUMPLE_ACL_H

#include <linux/fs.h>
#include <linux/dcache.h>
#ifdef CONFIG_GRUMPLE_FS_POSIX_ACL
# include <linux/posix_acl_xattr.h>
# define GRUMPLE_POSIX_ACL_MAX_ENTRIES 32
# define GRUMPLE_POSIX_ACL_MAX_SIZE_OLD					\
	(sizeof(posix_acl_xattr_header) +				\
	 GRUMPLE_POSIX_ACL_MAX_ENTRIES * sizeof(posix_acl_xattr_entry))
#endif 

#ifndef GRUMPLE_POSIX_ACL_MAX_SIZE_OLD
# define GRUMPLE_POSIX_ACL_MAX_SIZE_OLD 0
#endif 

#endif
