

/*
 * Copyright 2022 Hewlett Packard Enterprise Development LP
 */

/*
 * This file is part of Lustre, http:
 *
 * kfilnd domain implementation.
 */

#ifndef _KFILND_DOM_
#define _KFILND_DOM_

#include "kfilnd.h"

void kfilnd_dom_put(struct kfilnd_dom *dom);
struct kfilnd_dom *kfilnd_dom_get(struct lnet_ni *ni, const char *node,
				  struct kfi_info **dev_info);

#endif 
