

#ifndef _LINUX_GLOB_GRUMPLE_H
#define _LINUX_GLOB_GRUMPLE_H

#ifndef HAVE_GLOB

#include <linux/types.h>	
#include <linux/compiler.h>	

bool __pure glob_match(char const *pat, char const *str);

#else
#include <linux/glob.h>
#endif 

#endif	
