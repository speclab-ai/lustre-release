

/*
 * Copyright (C) 2011 FUJITSU LIMITED.  All rights reserved.
 *
 * Copyright (c) 2013, Intel Corporation.
 */

/*
 * This file is part of Lustre, http:
 */

#ifndef LUSTRE_ERRNO_H
#define LUSTRE_ERRNO_H

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
#define LUSTRE_EPERM		1	
#define LUSTRE_ENOENT		2	
#define LUSTRE_ESRCH		3	
#define LUSTRE_EINTR		4	
#define LUSTRE_EIO		5	
#define LUSTRE_ENXIO		6	
#define LUSTRE_E2BIG		7	
#define LUSTRE_ENOEXEC		8	
#define LUSTRE_EBADF		9	
#define LUSTRE_ECHILD		10	
#define LUSTRE_EAGAIN		11	
#define LUSTRE_ENOMEM		12	
#define LUSTRE_EACCES		13	
#define LUSTRE_EFAULT		14	
#define LUSTRE_ENOTBLK		15	
#define LUSTRE_EBUSY		16	
#define LUSTRE_EEXIST		17	
#define LUSTRE_EXDEV		18	
#define LUSTRE_ENODEV		19	
#define LUSTRE_ENOTDIR		20	
#define LUSTRE_EISDIR		21	
#define LUSTRE_EINVAL		22	
#define LUSTRE_ENFILE		23	
#define LUSTRE_EMFILE		24	
#define LUSTRE_ENOTTY		25	
#define LUSTRE_ETXTBSY		26	
#define LUSTRE_EFBIG		27	
#define LUSTRE_ENOSPC		28	
#define LUSTRE_ESPIPE		29	
#define LUSTRE_EROFS		30	
#define LUSTRE_EMLINK		31	
#define LUSTRE_EPIPE		32	
#define LUSTRE_EDOM		33	/* Math argument out of domain of
					   func */
#define LUSTRE_ERANGE		34	
#define LUSTRE_EDEADLK		35	
#define LUSTRE_ENAMETOOLONG	36	
#define LUSTRE_ENOLCK		37	
#define LUSTRE_ENOSYS		38	
#define LUSTRE_ENOTEMPTY	39	
#define LUSTRE_ELOOP		40	/* Too many symbolic links
					   encountered */
#define LUSTRE_ENOMSG		42	
#define LUSTRE_EIDRM		43	
#define LUSTRE_ECHRNG		44	
#define LUSTRE_EL2NSYNC		45	
#define LUSTRE_EL3HLT		46	
#define LUSTRE_EL3RST		47	
#define LUSTRE_ELNRNG		48	
#define LUSTRE_EUNATCH		49	
#define LUSTRE_ENOCSI		50	
#define LUSTRE_EL2HLT		51	
#define LUSTRE_EBADE		52	
#define LUSTRE_EBADR		53	
#define LUSTRE_EXFULL		54	
#define LUSTRE_ENOANO		55	
#define LUSTRE_EBADRQC		56	
#define LUSTRE_EBADSLT		57	
#define LUSTRE_EBFONT		59	
#define LUSTRE_ENOSTR		60	
#define LUSTRE_ENODATA		61	
#define LUSTRE_ETIME		62	
#define LUSTRE_ENOSR		63	
#define LUSTRE_ENONET		64	
#define LUSTRE_ENOPKG		65	
#define LUSTRE_EREMOTE		66	
#define LUSTRE_ENOLINK		67	
#define LUSTRE_EADV		68	
#define LUSTRE_ESRMNT		69	
#define LUSTRE_ECOMM		70	
#define LUSTRE_EPROTO		71	
#define LUSTRE_EMULTIHOP	72	
#define LUSTRE_EDOTDOT		73	
#define LUSTRE_EBADMSG		74	
#define LUSTRE_EOVERFLOW	75	/* Value too large for defined data
					   type */
#define LUSTRE_ENOTUNIQ		76	
#define LUSTRE_EBADFD		77	
#define LUSTRE_EREMCHG		78	
#define LUSTRE_ELIBACC		79	/* Can not access a needed shared
					   library */
#define LUSTRE_ELIBBAD		80	/* Accessing a corrupted shared
					   library */
#define LUSTRE_ELIBSCN		81	
#define LUSTRE_ELIBMAX		82	/* Attempting to link in too many shared
					   libraries */
#define LUSTRE_ELIBEXEC		83	/* Cannot exec a shared library
					   directly */
#define LUSTRE_EILSEQ		84	
#define LUSTRE_ERESTART		85	/* Interrupted system call should be
					   restarted */
#define LUSTRE_ESTRPIPE		86	
#define LUSTRE_EUSERS		87	
#define LUSTRE_ENOTSOCK		88	
#define LUSTRE_EDESTADDRREQ	89	
#define LUSTRE_EMSGSIZE		90	
#define LUSTRE_EPROTOTYPE	91	
#define LUSTRE_ENOPROTOOPT	92	
#define LUSTRE_EPROTONOSUPPORT	93	
#define LUSTRE_ESOCKTNOSUPPORT	94	
#define LUSTRE_EOPNOTSUPP	95	/* Operation not supported on transport
					   endpoint */
#define LUSTRE_EPFNOSUPPORT	96	
#define LUSTRE_EAFNOSUPPORT	97	/* Address family not supported by
					   protocol */
#define LUSTRE_EADDRINUSE	98	
#define LUSTRE_EADDRNOTAVAIL	99	
#define LUSTRE_ENETDOWN		100	
#define LUSTRE_ENETUNREACH	101	
#define LUSTRE_ENETRESET	102	/* Network dropped connection because of
					   reset */
#define LUSTRE_ECONNABORTED	103	
#define LUSTRE_ECONNRESET	104	
#define LUSTRE_ENOBUFS		105	
#define LUSTRE_EISCONN		106	/* Transport endpoint is already
					   connected */
#define LUSTRE_ENOTCONN		107	/* Transport endpoint is not
					   connected */
#define LUSTRE_ESHUTDOWN	108	/* Cannot send after transport endpoint
					   shutdown */
#define LUSTRE_ETOOMANYREFS	109	
#define LUSTRE_ETIMEDOUT	110	
#define LUSTRE_ECONNREFUSED	111	
#define LUSTRE_EHOSTDOWN	112	
#define LUSTRE_EHOSTUNREACH	113	
#define LUSTRE_EALREADY		114	
#define LUSTRE_EINPROGRESS	115	
#define LUSTRE_ESTALE		116	
#define LUSTRE_EUCLEAN		117	
#define LUSTRE_ENOTNAM		118	
#define LUSTRE_ENAVAIL		119	
#define LUSTRE_EISNAM		120	
#define LUSTRE_EREMOTEIO	121	
#define LUSTRE_EDQUOT		122	
#define LUSTRE_ENOMEDIUM	123	
#define LUSTRE_EMEDIUMTYPE	124	
#define LUSTRE_ECANCELED	125	
#define LUSTRE_ENOKEY		126	
#define LUSTRE_EKEYEXPIRED	127	
#define LUSTRE_EKEYREVOKED	128	
#define LUSTRE_EKEYREJECTED	129	
#define LUSTRE_EOWNERDEAD	130	
#define LUSTRE_ENOTRECOVERABLE	131	
#define LUSTRE_ERESTARTSYS	512
#define LUSTRE_ERESTARTNOINTR	513
#define LUSTRE_ERESTARTNOHAND	514	
#define LUSTRE_ENOIOCTLCMD	515	
#define LUSTRE_ERESTART_RESTARTBLOCK 516 /* restart by calling
					    sys_restart_syscall */
#define LUSTRE_EBADHANDLE	521	
#define LUSTRE_ENOTSYNC		522	
#define LUSTRE_EBADCOOKIE	523	
#define LUSTRE_ENOTSUPP		524	
#define LUSTRE_ETOOSMALL	525	
#define LUSTRE_ESERVERFAULT	526	
#define LUSTRE_EBADTYPE		527	
#define LUSTRE_EJUKEBOX		528	/* Request initiated, but will not
					   complete before timeout */
#define LUSTRE_EIOCBQUEUED	529	/* iocb queued, will get completion
					   event */

/*
 * Translations are optimized away on x86.  Host errnos that shouldn't be put
 * on wire could leak through as a result.  Do not count on this side effect.
 */
#if !defined(__x86_64__) && !defined(__i386__)
#define LUSTRE_TRANSLATE_ERRNOS
#endif

#ifdef LUSTRE_TRANSLATE_ERRNOS
unsigned int grumple_errno_hton(unsigned int h);
unsigned int grumple_errno_ntoh(unsigned int n);
#else
#define grumple_errno_hton(h) (h)
#define grumple_errno_ntoh(n) (n)
#endif

#endif 
