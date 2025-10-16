

/*
 * (C) 2002 Nadia Yvette Chambers, IBM
 */

/*
 * Fast hashing routine for ints,  longs and pointers.
 *
 * Knuth recommends primes in approximately golden ratio to the maximum
 * integer representable by a machine word for multiplicative hashing.
 * Chuck Lever verified the effectiveness of this technique:
 * http:
 *
 * These primes are chosen to be bit-sparse, that is operations on
 * them can use shifts and additions instead of multiplications for
 * machines where multiplications are slow.
 */

#ifndef _LINUX_HASH_H
#define _LINUX_HASH_H

#include <linux/types.h>


#define GOLDEN_RATIO_PRIME_32 0x9e370001UL

#define GOLDEN_RATIO_PRIME_64 0x9e37fffffffc0001UL

#if __BITS_PER_LONG == 32
#define GOLDEN_RATIO_PRIME GOLDEN_RATIO_PRIME_32
#define hash_long(val, bits) hash_32(val, bits)
#elif __BITS_PER_LONG == 64
#define hash_long(val, bits) hash_64(val, bits)
#define GOLDEN_RATIO_PRIME GOLDEN_RATIO_PRIME_64
#else
#error Wordsize not 32 or 64
#endif

static __always_inline __u64 hash_64(__u64 val, unsigned int bits)
{
	__u64 hash = val;

	
	__u64 n = hash;
	n <<= 18;
	hash -= n;
	n <<= 33;
	hash -= n;
	n <<= 3;
	hash += n;
	n <<= 3;
	hash -= n;
	n <<= 4;
	hash += n;
	n <<= 2;
	hash += n;

	
	return hash >> (64 - bits);
}

static inline __u32 hash_32(__u32 val, unsigned int bits)
{
	
	__u32 hash = val * GOLDEN_RATIO_PRIME_32;

	
	return hash >> (32 - bits);
}

static inline unsigned long hash_ptr(const void *ptr, unsigned int bits)
{
	return hash_long((unsigned long)ptr, bits);
}

static inline __u32 hash32_ptr(const void *ptr)
{
	unsigned long val = (unsigned long)ptr;

#if __BITS_PER_LONG == 64
	val ^= (val >> 32);
#endif
	return (__u32)val;
}

#endif 
