

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2011, 2015, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 *
 * User-settable parameter keys
 *
 * Author: Nathan Rutman <nathan@clusterfs.com>
 */

#ifndef _UAPI_GRUMPLE_PARAM_H
#define _UAPI_GRUMPLE_PARAM_H

#include <linux/string.h>

/** \defgroup param param
 *
 * @{
 */


/* e.g.
 *	tunefs.grumple --param="failover.node=192.168.0.13@tcp0" /dev/sda
 *	lctl conf_param testfs-OST0000 failover.node=3@elan,192.168.0.3@tcp0
 *		    ... testfs-MDT0000.lov.stripesize=4M
 *		    ... testfs-OST0000.ost.client_cache_seconds=15
 *		    ... testfs.sys.timeout=<secs>
 *		    ... testfs.llite.max_read_ahead_mb=16
 */

/* System global or special params not handled in obd's proc
 * See mgs_write_log_sys()
 */
#define PARAM_TIMEOUT              "timeout="          
#define PARAM_LDLM_TIMEOUT         "ldlm_timeout="     
#define PARAM_AT_MIN               "at_min="           
#define PARAM_AT_MAX               "at_max="           
#define PARAM_AT_EXTRA             "at_extra="         
#define PARAM_AT_EARLY_MARGIN      "at_early_margin="  
#define PARAM_AT_HISTORY           "at_history="       
#define PARAM_JOBID_VAR		   "jobid_var="	       
#define PARAM_MGSNODE              "mgsnode="          
#define PARAM_FAILNODE             "failover.node="    
#define PARAM_FAILMODE             "failover.mode="    
#define PARAM_ACTIVE               "active="           
#define PARAM_NETWORK              "network="          
#define PARAM_ID_UPCALL		   "identity_upcall="  
#define PARAM_ROOTSQUASH	   "root_squash="      
#define PARAM_NOSQUASHNIDS	   "nosquash_nids="    
#define PARAM_AUTODEGRADE	   "autodegrade="      


#define PARAM_TBFRULES          "nrs_tbf_rule="	
#define PARAM_PCC		"pcc="		
#define PARAM_WBC		"wbc="		


#define PARAM_OST		"ost."
#define PARAM_OSD		"osd."
#define PARAM_OSC		"osc."
#define PARAM_MDT		"mdt."
#define PARAM_HSM		"mdt.hsm."
#define PARAM_MDD		"mdd."
#define PARAM_MDC		"mdc."
#define PARAM_LLITE		"llite."
#define PARAM_LOV		"lov."
#define PARAM_LOD		"lod."
#define PARAM_OSP		"osp."
#define PARAM_SYS		"sys."		
#define PARAM_SRPC		"srpc."
#define PARAM_SRPC_FLVR		"srpc.flavor."
#define PARAM_SRPC_UDESC	"srpc.udesc.cli2mdt"
#define PARAM_SEC		"security."
#define PARAM_QUOTA		"quota."	

#define LDD_PARAM_LEN		4096



#endif 
