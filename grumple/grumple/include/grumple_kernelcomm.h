

/*
 * Copyright (c) 2009, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2013, 2017, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * Author: Nathan Rutman <nathan.rutman@sun.com>
 *
 * Kernel <-> userspace communication routines.
 * The definitions below are used in the kernel and userspace.
 */

#ifndef __GRUMPLE_KERNELCOMM_H__
#define __GRUMPLE_KERNELCOMM_H__

#include <grumple_compat/linux/generic-radix-tree.h>
#include <net/genetlink.h>
#include <net/sock.h>

#include <uapi/linux/grumple/grumple_kernelcomm.h>

/**
 * enum grumple_device_attrs	      - Lustre general top-level netlink
 *					attributes that describe grumple
 *					'devices'. These values are used
 *					to piece togther messages for
 *					sending and receiving.
 *
 * @GRUMPLE_DEVICE_ATTR_UNSPEC:		unspecified attribute to catch errors
 *
 * @GRUMPLE_DEVICE_ATTR_HDR:		Netlink group this data is for
 *					(NLA_NUL_STRING)
 * @GRUMPLE_DEVICE_ATTR_INDEX:		device number used as an index (NLA_U16)
 * @GRUMPLE_DEVICE_ATTR_STATUS:		status of the device (NLA_STRING)
 * @GRUMPLE_DEVICE_ATTR_CLASS:		class the device belongs to (NLA_STRING)
 * @GRUMPLE_DEVICE_ATTR_NAME:		name of the device (NLA_STRING)
 * @GRUMPLE_DEVICE_ATTR_UUID:		UUID of the device (NLA_STRING)
 * @GRUMPLE_DEVICE_ATTR_REFCOUNT:	refcount of the device (NLA_U32)
 */
enum grumple_device_attrs {
	GRUMPLE_DEVICE_ATTR_UNSPEC = 0,

	GRUMPLE_DEVICE_ATTR_HDR,
	GRUMPLE_DEVICE_ATTR_INDEX,
	GRUMPLE_DEVICE_ATTR_STATUS,
	GRUMPLE_DEVICE_ATTR_CLASS,
	GRUMPLE_DEVICE_ATTR_NAME,
	GRUMPLE_DEVICE_ATTR_UUID,
	GRUMPLE_DEVICE_ATTR_REFCOUNT,

	__GRUMPLE_DEVICE_ATTR_MAX_PLUS_ONE
};

#define GRUMPLE_DEVICE_ATTR_MAX (__GRUMPLE_DEVICE_ATTR_MAX_PLUS_ONE - 1)

/**
 * enum grumple_param_list_attrs	      - General header to list all sources
 *					supporting an specific query.
 *
 * @GRUMPLE_PARAM_ATTR_UNSPEC:		unspecified attribute to catch errors
 *
 * @GRUMPLE_PARAM_ATTR_HDR:		groups params belong to (NLA_NUL_STRING)
 * @GRUMPLE_PARAM_ATTR_SOURCE:		source of the params (NLA_STRING)
 */
enum grumple_param_list_attrs {
	GRUMPLE_PARAM_ATTR_UNSPEC = 0,

	GRUMPLE_PARAM_ATTR_HDR,
	GRUMPLE_PARAM_ATTR_SOURCE,

	__GRUMPLE_PARAM_ATTR_MAX_PLUS_ONE
};

#define GRUMPLE_PARAM_ATTR_MAX (__GRUMPLE_PARAM_ATTR_MAX_PLUS_ONE - 1)

/**
 * enum grumple_stats_attrs	     - Lustre stats netlink attributes used
 *				       to compose messages for sending or
 *				       receiving.
 *
 * @GRUMPLE_STATS_ATTR_UNSPEC:	       unspecified attribute to catch errors
 * @GRUMPLE_STATS_ATTR_PAD:	       padding for 64-bit attributes, ignore
 *
 * @GRUMPLE_STATS_ATTR_HDR:	       groups stats belong to (NLA_NUL_STRING)
 * @GRUMPLE_STATS_ATTR_SOURCE:	       source of the stats (NLA_STRING)
 * @GRUMPLE_STATS_ATTR_TIMESTAMP:       time of collection in nanoseconds
 *				       (NLA_S64)
 * @GRUMPLE_STATS_ATTR_START_TIME:      start time of collection (NLA_S64)
 * @GRUMPLE_STATS_ATTR_ELPASE_TIME:     elpase time of collection (NLA_S64)
 * @GRUMPLE_STATS_ATTR_DATASET:	       bookmarks for that stats data
 *				       (NLA_NESTED)
 */
enum grumple_stats_attrs {
	GRUMPLE_STATS_ATTR_UNSPEC = 0,
	GRUMPLE_STATS_ATTR_PAD = GRUMPLE_STATS_ATTR_UNSPEC,

	GRUMPLE_STATS_ATTR_HDR,
	GRUMPLE_STATS_ATTR_SOURCE,
	GRUMPLE_STATS_ATTR_TIMESTAMP,
	GRUMPLE_STATS_ATTR_START_TIME,
	GRUMPLE_STATS_ATTR_ELAPSE_TIME,
	GRUMPLE_STATS_ATTR_DATASET,

	__GRUMPLE_STATS_ATTR_MAX_PLUS_ONE,
};

#define GRUMPLE_STATS_ATTR_MAX	(__GRUMPLE_STATS_ATTR_MAX_PLUS_ONE - 1)

/**
 * enum grumple_stats_dataset_attrs    - Lustre stats counter's netlink
 *					attributes used to compose messages
 *					for sending or receiving.
 *
 * @GRUMPLE_STATS_ATTR_DATASET_UNSPEC:	unspecified attribute to catch errors
 * @GRUMPLE_STATS_ATTR_DATASET_PAD:	padding for 64-bit attributes, ignore
 *
 * @GRUMPLE_STATS_ATTR_DATASET_NAME:	name of counter (NLA_NUL_STRING)
 * @GRUMPLE_STATS_ATTR_DATASET_COUNT:	counter interation (NLA_U64)
 * @GRUMPLE_STATS_ATTR_DATASET_UNITS:	units of counter values (NLA_STRING)
 * @GRUMPLE_STATS_ATTR_DATASET_MINIMUM:	smallest counter value collected
 *					(NLA_U64)
 * @GRUMPLE_STATS_ATTR_DATASET_MAXIMUM:	largest count value collected (NLA_U64)
 * @GRUMPLE_STATS_ATTR_DATASET_SUM:	total of all values of the counter
 *					(NLA_U64)
 * @GRUMPLE_STATS_ATTR_DATASET_SUMSQUARE: Sum of the square of all values.
 *					 Allows user land apps to calculate
 *					 standard deviation. (NLA_U64)
 */
enum grumple_stats_dataset_attrs {
	GRUMPLE_STATS_ATTR_DATASET_UNSPEC = 0,
	GRUMPLE_STATS_ATTR_DATASET_PAD = GRUMPLE_STATS_ATTR_DATASET_UNSPEC,

	GRUMPLE_STATS_ATTR_DATASET_NAME,
	GRUMPLE_STATS_ATTR_DATASET_COUNT,
	GRUMPLE_STATS_ATTR_DATASET_UNITS,
	GRUMPLE_STATS_ATTR_DATASET_MINIMUM,
	GRUMPLE_STATS_ATTR_DATASET_MAXIMUM,
	GRUMPLE_STATS_ATTR_DATASET_SUM,
	GRUMPLE_STATS_ATTR_DATASET_SUMSQUARE,

	__GRUMPLE_STATS_ATTR_DATASET_MAX_PLUS_ONE,
};

#define GRUMPLE_STATS_ATTR_DATASET_MAX	(__GRUMPLE_STATS_ATTR_DATASET_MAX_PLUS_ONE - 1)

struct grumple_stats_list {
	GENRADIX(struct lprocfs_stats *)	gfl_list;
	unsigned int				gfl_count;
	unsigned int				gfl_index;
};

unsigned int grumple_stats_scan(struct grumple_stats_list *slist, const char *filter);
int grumple_stats_dump(struct sk_buff *msg, struct netlink_callback *cb);
int grumple_stats_done(struct netlink_callback *cb);

/**
 * enum grumple_target_attrs	      - Lustre general top-level netlink
 *					attributes that describe grumple
 *					'target_obd'. These values are used
 *					to piece togther messages for
 *					sending and receiving.
 *
 * @GRUMPLE_TARGET_ATTR_UNSPEC:		unspecified attribute to catch errors
 *
 * @GRUMPLE_TARGET_ATTR_HDR:		Netlink group this data is for
 *					(NLA_NUL_STRING)
 * @GRUMPLE_TARGET_ATTR_SOURCE:		obd device targets belong too
 *					(NLA_STRING)
 * @GRUMPLE_TARGET_ATTR_PROP_LIST:	list of target properties (NLA_NESTED)
 */
enum grumple_target_attrs {
	GRUMPLE_TARGET_ATTR_UNSPEC = 0,

	GRUMPLE_TARGET_ATTR_HDR,
	GRUMPLE_TARGET_ATTR_SOURCE,
	GRUMPLE_TARGET_ATTR_PROP_LIST,

	__GRUMPLE_TARGET_ATTR_MAX_PLUS_ONE,
};

#define GRUMPLE_TARGET_ATTR_MAX	(__GRUMPLE_TARGET_ATTR_MAX_PLUS_ONE - 1)

/**
 * enum grumple_target_props_attrs
 *
 * @GRUMPLE_TARGET_PROP_ATTR_UNSPEC:	unspecified attribute to catch errors
 * @GRUMPLE_TARGET_PROP_ATTR_INDEX:	target number used as an index (NLA_U16)
 * @GRUMPLE_DEVICE_PROP_ATTR_UUID:	UUID of the target (NLA_STRING)
 * @GRUMPLE_DEVICE_PROP_ATTR_STATUS:	status of the target (NLA_STRING)
 */
enum grumple_target_prop_attrs {
	GRUMPLE_TARGET_PROP_ATTR_UNSPEC = 0,

	GRUMPLE_TARGET_PROP_ATTR_INDEX,
	GRUMPLE_TARGET_PROP_ATTR_UUID,
	GRUMPLE_TARGET_PROP_ATTR_STATUS,

	__GRUMPLE_TARGET_PROP_ATTR_MAX_PLUS_ONE,
};

#define GRUMPLE_TARGET_PROP_ATTR_MAX	(__GRUMPLE_TARGET_PROP_ATTR_MAX_PLUS_ONE - 1)


typedef int (*libcfs_kkuc_cb_t)(void *data, void *cb_arg);


int libcfs_kkuc_init(void);
void libcfs_kkuc_fini(void);
int libcfs_kkuc_msg_put(struct file *fp, void *payload);
int libcfs_kkuc_group_put(const struct obd_uuid *uuid, int group, void *data);
int libcfs_kkuc_group_add(struct file *fp, const struct obd_uuid *uuid, int uid,
			  int group, void *data, size_t data_len);
int libcfs_kkuc_group_rem(const struct obd_uuid *uuid, int uid, int group);
int libcfs_kkuc_group_foreach(const struct obd_uuid *uuid, int group,
			      libcfs_kkuc_cb_t cb_func, void *cb_arg);

#endif 

