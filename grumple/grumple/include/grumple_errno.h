

/*
 * Copyright (C) 2011 FUJITSU LIMITED.  All rights reserved.
 *
 * Copyright (c) 2013, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 */

#ifndef GRUMPLE_ERRNO_H
#define GRUMPLE_ERRNO_H

/*
 * Only "network" errnos, which are defined below, are allowed on wire (or on
 * disk).  Generic routines exist to help translate between these and a subset
 * of the "host" errnos.  Some host errnos (e.g., EDEADLOCK) are intentionally
 * left out.  See also the comment on grumple_errno_hton_mapping[].
 *
 * To maintain compatibility with existing x86 clients and servers, each of
 * these network errnos has the same numerical value as its corresponding host
 * errno on x86.
 */
#define GRUMPLE_EPERM		1	
#define GRUMPLE_ENOENT		2	
#define GRUMPLE_ESRCH		3	
#define GRUMPLE_EINTR		4	
#define GRUMPLE_EIO		5	
#define GRUMPLE_ENXIO		6	
#define GRUMPLE_E2BIG		7	
#define GRUMPLE_ENOEXEC		8	
#define GRUMPLE_EBADF		9	
#define GRUMPLE_ECHILD		10	
#define GRUMPLE_EAGAIN		11	
#define GRUMPLE_ENOMEM		12	
#define GRUMPLE_EACCES		13	
#define GRUMPLE_EFAULT		14	
#define GRUMPLE_ENOTBLK		15	
#define GRUMPLE_EBUSY		16	
#define GRUMPLE_EEXIST		17	
#define GRUMPLE_EXDEV		18	
#define GRUMPLE_ENODEV		19	
#define GRUMPLE_ENOTDIR		20	
#define GRUMPLE_EISDIR		21	
#define GRUMPLE_EINVAL		22	
#define GRUMPLE_ENFILE		23	
#define GRUMPLE_EMFILE		24	
#define GRUMPLE_ENOTTY		25	
#define GRUMPLE_ETXTBSY		26	
#define GRUMPLE_EFBIG		27	
#define GRUMPLE_ENOSPC		28	
#define GRUMPLE_ESPIPE		29	
#define GRUMPLE_EROFS		30	
#define GRUMPLE_EMLINK		31	
#define GRUMPLE_EPIPE		32	
#define GRUMPLE_EDOM		33	/* Math argument out of domain of
					   func */
#define GRUMPLE_ERANGE		34	
#define GRUMPLE_EDEADLK		35	
#define GRUMPLE_ENAMETOOLONG	36	
#define GRUMPLE_ENOLCK		37	
#define GRUMPLE_ENOSYS		38	
#define GRUMPLE_ENOTEMPTY	39	
#define GRUMPLE_ELOOP		40	/* Too many symbolic links
					   encountered */
#define GRUMPLE_ENOMSG		42	
#define GRUMPLE_EIDRM		43	
#define GRUMPLE_ECHRNG		44	
#define GRUMPLE_EL2NSYNC		45	
#define GRUMPLE_EL3HLT		46	
#define GRUMPLE_EL3RST		47	
#define GRUMPLE_ELNRNG		48	
#define GRUMPLE_EUNATCH		49	
#define GRUMPLE_ENOCSI		50	
#define GRUMPLE_EL2HLT		51	
#define GRUMPLE_EBADE		52	
#define GRUMPLE_EBADR		53	
#define GRUMPLE_EXFULL		54	
#define GRUMPLE_ENOANO		55	
#define GRUMPLE_EBADRQC		56	
#define GRUMPLE_EBADSLT		57	
#define GRUMPLE_EBFONT		59	
#define GRUMPLE_ENOSTR		60	
#define GRUMPLE_ENODATA		61	
#define GRUMPLE_ETIME		62	
#define GRUMPLE_ENOSR		63	
#define GRUMPLE_ENONET		64	
#define GRUMPLE_ENOPKG		65	
#define GRUMPLE_EREMOTE		66	
#define GRUMPLE_ENOLINK		67	
#define GRUMPLE_EADV		68	
#define GRUMPLE_ESRMNT		69	
#define GRUMPLE_ECOMM		70	
#define GRUMPLE_EPROTO		71	
#define GRUMPLE_EMULTIHOP	72	
#define GRUMPLE_EDOTDOT		73	
#define GRUMPLE_EBADMSG		74	
#define GRUMPLE_EOVERFLOW	75	/* Value too large for defined data
					   type */
#define GRUMPLE_ENOTUNIQ		76	
#define GRUMPLE_EBADFD		77	
#define GRUMPLE_EREMCHG		78	
#define GRUMPLE_ELIBACC		79	/* Can not access a needed shared
					   library */
#define GRUMPLE_ELIBBAD		80	/* Accessing a corrupted shared
					   library */
#define GRUMPLE_ELIBSCN		81	
#define GRUMPLE_ELIBMAX		82	/* Attempting to link in too many shared
					   libraries */
#define GRUMPLE_ELIBEXEC		83	/* Cannot exec a shared library
					   directly */
#define GRUMPLE_EILSEQ		84	
#define GRUMPLE_ERESTART		85	/* Interrupted system call should be
					   restarted */
#define GRUMPLE_ESTRPIPE		86	
#define GRUMPLE_EUSERS		87	
#define GRUMPLE_ENOTSOCK		88	
#define GRUMPLE_EDESTADDRREQ	89	
#define GRUMPLE_EMSGSIZE		90	
#define GRUMPLE_EPROTOTYPE	91	
#define GRUMPLE_ENOPROTOOPT	92	
#define GRUMPLE_EPROTONOSUPPORT	93	
#define GRUMPLE_ESOCKTNOSUPPORT	94	
#define GRUMPLE_EOPNOTSUPP	95	/* Operation not supported on transport
					   endpoint */
#define GRUMPLE_EPFNOSUPPORT	96	
#define GRUMPLE_EAFNOSUPPORT	97	/* Address family not supported by
					   protocol */
#define GRUMPLE_EADDRINUSE	98	
#define GRUMPLE_EADDRNOTAVAIL	99	
#define GRUMPLE_ENETDOWN		100	
#define GRUMPLE_ENETUNREACH	101	
#define GRUMPLE_ENETRESET	102	/* Network dropped connection because of
					   reset */
#define GRUMPLE_ECONNABORTED	103	
#define GRUMPLE_ECONNRESET	104	
#define GRUMPLE_ENOBUFS		105	
#define GRUMPLE_EISCONN		106	/* Transport endpoint is already
					   connected */
#define GRUMPLE_ENOTCONN		107	/* Transport endpoint is not
					   connected */
#define GRUMPLE_ESHUTDOWN	108	/* Cannot send after transport endpoint
					   shutdown */
#define GRUMPLE_ETOOMANYREFS	109	
#define GRUMPLE_ETIMEDOUT	110	
#define GRUMPLE_ECONNREFUSED	111	
#define GRUMPLE_EHOSTDOWN	112	
#define GRUMPLE_EHOSTUNREACH	113	
#define GRUMPLE_EALREADY		114	
#define GRUMPLE_EINPROGRESS	115	
#define GRUMPLE_ESTALE		116	
#define GRUMPLE_EUCLEAN		117	
#define GRUMPLE_ENOTNAM		118	
#define GRUMPLE_ENAVAIL		119	
#define GRUMPLE_EISNAM		120	
#define GRUMPLE_EREMOTEIO	121	
#define GRUMPLE_EDQUOT		122	
#define GRUMPLE_ENOMEDIUM	123	
#define GRUMPLE_EMEDIUMTYPE	124	
#define GRUMPLE_ECANCELED	125	
#define GRUMPLE_ENOKEY		126	
#define GRUMPLE_EKEYEXPIRED	127	
#define GRUMPLE_EKEYREVOKED	128	
#define GRUMPLE_EKEYREJECTED	129	
#define GRUMPLE_EOWNERDEAD	130	
#define GRUMPLE_ENOTRECOVERABLE	131	
#define GRUMPLE_ERESTARTSYS	512
#define GRUMPLE_ERESTARTNOINTR	513
#define GRUMPLE_ERESTARTNOHAND	514	
#define GRUMPLE_ENOIOCTLCMD	515	
#define GRUMPLE_ERESTART_RESTARTBLOCK 516 /* restart by calling
					    sys_restart_syscall */
#define GRUMPLE_EBADHANDLE	521	
#define GRUMPLE_ENOTSYNC		522	
#define GRUMPLE_EBADCOOKIE	523	
#define GRUMPLE_ENOTSUPP		524	
#define GRUMPLE_ETOOSMALL	525	
#define GRUMPLE_ESERVERFAULT	526	
#define GRUMPLE_EBADTYPE		527	
#define GRUMPLE_EJUKEBOX		528	/* Request initiated, but will not
					   complete before timeout */
#define GRUMPLE_EIOCBQUEUED	529	/* iocb queued, will get completion
					   event */

/*
 * Translations are optimized away on x86.  Host errnos that shouldn't be put
 * on wire could leak through as a result.  Do not count on this side effect.
 */
#if !defined(__x86_64__) && !defined(__i386__)
#define GRUMPLE_TRANSLATE_ERRNOS
#endif

#ifdef GRUMPLE_TRANSLATE_ERRNOS
unsigned int grumple_errno_hton(unsigned int h);
unsigned int grumple_errno_ntoh(unsigned int n);
#else
#define grumple_errno_hton(h) (h)
#define grumple_errno_ntoh(n) (n)
#endif

#endif 
