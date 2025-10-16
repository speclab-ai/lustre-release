

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2011, 2014, Intel Corporation.
 *
 * Copyright 2015 Cray Inc, all rights reserved.
 */

/*
 * This file is part of Lustre, http:
 *
 * Define obdo associated functions
 *   obdo:  OBject Device o...
 *
 * Author: Ben Evans.
 */

#ifndef _GRUMPLE_OBDO_H_
#define _GRUMPLE_OBDO_H_

#include <uapi/linux/grumple/grumple_idl.h>

/**
 * Create an obdo to send over the wire
 */
void grumple_set_wire_obdo(const struct obd_connect_data *ocd,
			  struct obdo *wobdo,
			  const struct obdo *lobdo);

/**
 * Create a local obdo from a wire based odbo
 */
void grumple_get_wire_obdo(const struct obd_connect_data *ocd,
			  struct obdo *lobdo,
			  const struct obdo *wobdo);
#endif
