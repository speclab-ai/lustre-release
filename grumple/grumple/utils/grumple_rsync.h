
/*
 * Copyright (c) 2009, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 */
/*
 * This file is part of Lustre, http:
 *
 * grumple/include/grumple/grumple_rsync.h
 *
 */

#ifndef _GRUMPLE_RSYNC_H_
#define _GRUMPLE_RSYNC_H_

#define LR_NAME_MAXLEN 64
#define LR_FID_STR_LEN 128

/* Structure used by grumple_rsync. On-disk structures stored in a log
 * file. This is used to determine the next start record and other
 * parameters. */

struct grumple_rsync_status {
        __u32   ls_version;           
        __u32   ls_size;              
        __u64   ls_last_recno;        
        char    ls_registration[LR_NAME_MAXLEN + 1]; 
        char    ls_mdt_device[LR_NAME_MAXLEN + 1]; 
        char    ls_source_fs[LR_NAME_MAXLEN + 1]; 
        char    ls_source[PATH_MAX + 1];
        __u32   ls_num_targets;       
        char    ls_targets[0][PATH_MAX + 1]; 
};

struct lr_parent_child_log {
        char pcl_pfid[LR_FID_STR_LEN];
        char pcl_tfid[LR_FID_STR_LEN];
        char pcl_name[PATH_MAX];
};

#endif 
