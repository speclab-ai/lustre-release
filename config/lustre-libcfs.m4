AC_DEFUN([LIBCFS_CONFIG_CDEBUG], [
AC_MSG_CHECKING([whether to enable CDEBUG, CWARN])
AC_ARG_ENABLE([libcfs_cdebug],
	AS_HELP_STRING([--disable-libcfs-cdebug],
		[disable libcfs CDEBUG, CWARN]),
	[], [enable_libcfs_cdebug="yes"])
AC_MSG_RESULT([$enable_libcfs_cdebug])
AS_IF([test "x$enable_libcfs_cdebug" = xyes], [
	AC_DEFINE(CDEBUG_ENABLED, 1, [enable libcfs CDEBUG, CWARN])
	AC_SUBST(ENABLE_LIBCFS_CDEBUG, yes)
], [
	AC_SUBST(ENABLE_LIBCFS_CDEBUG, no)
])
AC_MSG_CHECKING([whether to enable ENTRY/EXIT])
AC_ARG_ENABLE([libcfs_trace],
	AS_HELP_STRING([--disable-libcfs-trace],
		[disable libcfs ENTRY/EXIT]),
	[], [enable_libcfs_trace="yes"])
AC_MSG_RESULT([$enable_libcfs_trace])
AS_IF([test "x$enable_libcfs_trace" = xyes], [
	AC_DEFINE(CDEBUG_ENTRY_EXIT, 1, [enable libcfs ENTRY/EXIT])
	AC_SUBST(ENABLE_LIBCFS_TRACE, yes)
], [
	AC_SUBST(ENABLE_LIBCFS_TRACE, no)
])
AC_MSG_CHECKING([whether to enable LASSERT, LASSERTF])
AC_ARG_ENABLE([libcfs_assert],
	AS_HELP_STRING([--disable-libcfs-assert],
		[disable libcfs LASSERT, LASSERTF]),
	[], [enable_libcfs_assert="yes"])
AC_MSG_RESULT([$enable_libcfs_assert])
AS_IF([test x$enable_libcfs_assert = xyes], [
	AC_DEFINE(LIBCFS_DEBUG, 1, [enable libcfs LASSERT, LASSERTF])
	AC_SUBST(ENABLE_LIBCFS_ASSERT, yes)
], [
	AC_SUBST(ENABLE_LIBCFS_ASSERT, no)
])
]) 
AC_DEFUN([LIBCFS_CONFIG_PANIC_DUMPLOG], [
AC_MSG_CHECKING([whether to use tunable 'panic_dumplog' support])
AC_ARG_ENABLE([panic_dumplog],
	AS_HELP_STRING([--enable-panic_dumplog],
		[enable panic_dumplog]),
	[], [enable_panic_dumplog="no"])
AC_MSG_RESULT([$enable_panic_dumplog])
AS_IF([test "x$enable_panic_dumplog" = xyes], [
	AC_DEFINE(LNET_DUMP_ON_PANIC, 1, [use dumplog on panic])
	AC_SUBST(ENABLE_PANIC_DUMPLOG, yes)
], [
	AC_SUBST(ENABLE_PANIC_DUMPLOG, no)
])
]) 
AC_DEFUN([LIBCFS_SRC_PREPARE_TO_WAIT_EVENT],[
	LB2_LINUX_TEST_SRC([prepare_to_wait_event], [
	],[
		prepare_to_wait_event(NULL, NULL, 0);
	])
])
AC_DEFUN([LIBCFS_PREPARE_TO_WAIT_EVENT],[
	LB2_MSG_LINUX_TEST_RESULT([if function 'prepare_to_wait_event' exist],
	[prepare_to_wait_event], [
		AC_DEFINE(HAVE_PREPARE_TO_WAIT_EVENT, 1,
			['prepare_to_wait_event' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_KERNEL_PARAM_OPS],[
	LB2_LINUX_TEST_SRC([kernel_param_ops], [
	],[
		struct kernel_param_ops ops;
		ops.set = NULL;
	])
])
AC_DEFUN([LIBCFS_KERNEL_PARAM_OPS],[
	LB2_MSG_LINUX_TEST_RESULT([if 'struct kernel_param_ops' exist],
	[kernel_param_ops], [
		AC_DEFINE(HAVE_KERNEL_PARAM_OPS, 1,
			['struct kernel_param_ops' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_MAPPING_AS_EXITING_FLAG], [
m4_pattern_allow([AS_EXITING])
	LB2_LINUX_TEST_SRC([mapping_exiting_exists], [
	],[
		enum mapping_flags flag = AS_EXITING;
		(void)flag;
	],[-Werror])
])
AC_DEFUN([LIBCFS_HAVE_MAPPING_AS_EXITING_FLAG], [
	LB2_MSG_LINUX_TEST_RESULT([if enum mapping_flags has AS_EXITING flag],
	[mapping_exiting_exists], [
		AC_DEFINE(HAVE_MAPPING_AS_EXITING_FLAG, 1,
			[enum mapping_flags has AS_EXITING flag])
	])
]) 
AC_DEFUN([LIBCFS_SRC_IOV_ITER_HAS_TYPE], [
	LB2_LINUX_TEST_SRC([iov_iter_has_type_member], [
	],[
		struct iov_iter iter = { .type = ITER_KVEC };
		(void)iter;
	],
	[-Werror])
])
AC_DEFUN([LIBCFS_IOV_ITER_HAS_TYPE], [
	LB2_MSG_LINUX_TEST_RESULT([if iov_iter has member type],
	[iov_iter_has_type_member], [
		AC_DEFINE(HAVE_IOV_ITER_HAS_TYPE_MEMBER, 1,
			[if iov_iter has member type])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_GLOB],[
	LB2_LINUX_TEST_SRC([glob_match], [
	],[
		return glob_match(NULL, NULL);
	],[-Werror])
])
AC_DEFUN([LIBCFS_HAVE_GLOB],[
	LB2_MSG_LINUX_TEST_RESULT([if 'glob_match()' exist],
	[glob_match], [
		AC_DEFINE(HAVE_GLOB, 1,
			[glob_match() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_WAIT_WOKEN],[
	LB2_LINUX_TEST_SRC([wait_woken], [
	],[
		wait_woken(NULL, 0, 0);
	])
])
AC_DEFUN([LIBCFS_WAIT_WOKEN],[
	LB2_MSG_LINUX_TEST_RESULT([if function 'wait_woken' exist],
	[wait_woken], [
		AC_DEFINE(HAVE_WAIT_WOKEN, 1,
			['wait_woken, is available'])
	])
]) 
AC_DEFUN([LIBCFS_SRC_KERNEL_PARAM_LOCK],[
	LB2_LINUX_TEST_SRC([kernel_param_lock], [
	],[
		kernel_param_lock(NULL);
		kernel_param_unlock(NULL);
	])
])
AC_DEFUN([LIBCFS_KERNEL_PARAM_LOCK],[
	LB2_MSG_LINUX_TEST_RESULT([if function 'kernel_param_[un]lock' exist],
	[kernel_param_lock], [
		AC_DEFINE(HAVE_KERNEL_PARAM_LOCK, 1,
			['kernel_param_[un]lock' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_STRSCPY_EXISTS], [
	LB2_LINUX_TEST_SRC([strscpy_exists], [
	],[
		char buf[129];
		strscpy(buf, "something", sizeof(buf));
	],[-Werror])
])
AC_DEFUN([LIBCFS_STRSCPY_EXISTS], [
	LB2_MSG_LINUX_TEST_RESULT([if kernel strscpy is available],
	[strscpy_exists], [
		AC_DEFINE(HAVE_STRSCPY, 1,
			[kernel strscpy is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_TOPOLOGY_SIBLING_CPUMASK],[
	LB2_LINUX_TEST_SRC([topology_sibling_cpumask], [
	],[
		const struct cpumask *mask;
		mask = topology_sibling_cpumask(0);
	])
])
AC_DEFUN([LIBCFS_HAVE_TOPOLOGY_SIBLING_CPUMASK],[
	LB2_MSG_LINUX_TEST_RESULT([if function 'topology_sibling_cpumask' exist],
	[topology_sibling_cpumask], [
		AC_DEFINE(HAVE_TOPOLOGY_SIBLING_CPUMASK, 1,
			[topology_sibling_cpumask is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_NETLINK_CALLBACK_START], [
	LB2_LINUX_TEST_SRC([cb_start], [
	],[
		struct genl_ops ops;
		ops.start = NULL;
	],[])
])
AC_DEFUN([LIBCFS_NETLINK_CALLBACK_START], [
	LB2_MSG_LINUX_TEST_RESULT([if struct genl_ops has start callback],
	[cb_start], [
		AC_DEFINE(HAVE_NETLINK_CALLBACK_START, 1,
			[struct genl_ops has 'start' callback])
	])
]) 
AC_DEFUN([LIBCFS_SRC_CRYPTO_HASH_HELPERS], [
	LB2_LINUX_TEST_SRC([crypto_hash_helpers], [
	],[
		crypto_ahash_alg_name(NULL);
		crypto_ahash_driver_name(NULL);
	])
])
AC_DEFUN([LIBCFS_CRYPTO_HASH_HELPERS], [
	LB2_MSG_LINUX_TEST_RESULT([if crypto hash helper functions exist],
	[crypto_hash_helpers], [
		AC_DEFINE(HAVE_CRYPTO_HASH_HELPERS, 1,
			[crypto hash helper functions are available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHASHTABLE_REPLACE], [
	LB2_LINUX_TEST_SRC([rhashtable_replace_fast], [
	],[
		const struct rhashtable_params params = { 0 };
		rhashtable_replace_fast(NULL, NULL, NULL, params);
	])
])
AC_DEFUN([LIBCFS_RHASHTABLE_REPLACE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'rhashtable_replace_fast' exists],
	[rhashtable_replace_fast], [
		AC_DEFINE(HAVE_RHASHTABLE_REPLACE, 1,
			[rhashtable_replace_fast() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_BROKEN_HASH_64], [
	LB2_LINUX_TEST_SRC([broken_hash_64], [
	],[
		int tmp = GOLDEN_RATIO_PRIME_64;
	])
])
AC_DEFUN([LIBCFS_BROKEN_HASH_64], [
	LB2_MSG_LINUX_TEST_RESULT([if kernel has fixed hash_64()],
	[broken_hash_64], [
		AC_DEFINE(HAVE_BROKEN_HASH_64, 1, [kernel hash_64() is broken])
	])
]) 
AC_DEFUN([LIBCFS_SRC_GET_USER_PAGES_6ARG], [
	LB2_LINUX_TEST_SRC([get_user_pages_6arg], [
	],[
		int rc;
		rc = get_user_pages(0, 0, 0, 0, NULL, NULL);
	])
])
AC_DEFUN([LIBCFS_GET_USER_PAGES_6ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'get_user_pages()' takes 6 arguments],
	[get_user_pages_6arg], [
		AC_DEFINE(HAVE_GET_USER_PAGES_6ARG, 1,
			[get_user_pages takes 6 arguments])
	])
]) 
AC_DEFUN([LIBCFS_SRC_STRINGHASH], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/stringhash.h], [-Werror])
])
AC_DEFUN([LIBCFS_STRINGHASH], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/stringhash.h], [
		AC_DEFINE(HAVE_STRINGHASH, 1,
			[stringhash.h is present])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHASHTABLE_INSERT_FAST], [
	LB2_LINUX_TEST_SRC([rhashtable_insert_fast], [
	],[
		const struct rhashtable_params params = { 0 };
		int rc;
		rc = __rhashtable_insert_fast(NULL, NULL, NULL, params);
	],
	[-Werror])
])
AC_DEFUN([LIBCFS_RHASHTABLE_INSERT_FAST], [
	LB2_MSG_LINUX_TEST_RESULT([if internal '__rhashtable_insert_fast()' returns int],
	[rhashtable_insert_fast], [
		AC_DEFINE(HAVE_HASHTABLE_INSERT_FAST_RETURN_INT, 1,
			  ['__rhashtable_insert_fast()' returns int])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHASHTABLE_WALK_INIT_3ARG], [
	LB2_LINUX_TEST_SRC([rhashtable_walk_init], [
	],[
		rhashtable_walk_init(NULL, NULL, GFP_KERNEL);
	])
])
AC_DEFUN([LIBCFS_RHASHTABLE_WALK_INIT_3ARG], [
	LB2_MSG_LINUX_TEST_RESULT([if 'rhashtable_walk_init' has 3 args],
	[rhashtable_walk_init], [
		AC_DEFINE(HAVE_3ARG_RHASHTABLE_WALK_INIT, 1,
			[rhashtable_walk_init() has 3 args])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHASHTABLE_LOOKUP], [
	LB2_LINUX_TEST_SRC([rhashtable_lookup], [
	],[
		const struct rhashtable_params params = { 0 };
		void *ret;
		ret = rhashtable_lookup(NULL, NULL, params);
	])
])
AC_DEFUN([LIBCFS_RHASHTABLE_LOOKUP], [
	LB2_MSG_LINUX_TEST_RESULT([if 'rhashtable_lookup' exist],
	[rhashtable_lookup], [
		AC_DEFINE(HAVE_RHASHTABLE_LOOKUP, 1,
			[rhashtable_lookup() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHLTABLE], [
	LB2_LINUX_TEST_SRC([rhtable], [
	],[
		struct rhltable *hlt = NULL;
		rhltable_destroy(hlt);
	])
])
AC_DEFUN([LIBCFS_RHLTABLE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'struct rhltable' exist],
	[rhtable], [
		AC_DEFINE(HAVE_RHLTABLE, 1, [struct rhltable exist])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHASHTABLE_WALK_ENTER], [
	LB2_LINUX_TEST_SRC([rhashtable_walk_enter], [
	],[
		rhashtable_walk_enter(NULL, NULL);
	])
])
AC_DEFUN([LIBCFS_RHASHTABLE_WALK_ENTER], [
	LB2_MSG_LINUX_TEST_RESULT([if 'rhashtable_walk_enter' exists],
	[rhashtable_walk_enter], [
		AC_DEFINE(HAVE_RHASHTABLE_WALK_ENTER, 1,
			[rhashtable_walk_enter() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_GET_USER_PAGES_GUP_FLAGS], [
	LB2_LINUX_TEST_SRC([get_user_pages_gup_flags], [
	],[
		int rc;
		rc = get_user_pages(0, 0, FOLL_WRITE, NULL, NULL);
	])
])
AC_DEFUN([LIBCFS_GET_USER_PAGES_GUP_FLAGS], [
	LB2_MSG_LINUX_TEST_RESULT([if 'get_user_pages()' takes gup_flags in arguments],
	[get_user_pages_gup_flags], [
		AC_DEFINE(HAVE_GET_USER_PAGES_GUP_FLAGS, 1,
			[get_user_pages takes gup_flags in arguments])
		])
]) 
AC_DEFUN([LIBCFS_SRC_HOTPLUG_STATE_MACHINE], [
	LB2_LINUX_TEST_SRC([cpu_hotplug_state_machine], [
	],[
		cpuhp_remove_state(CPUHP_BP_PREPARE_DYN);
	])
])
AC_DEFUN([LIBCFS_HOTPLUG_STATE_MACHINE], [
	LB2_MSG_LINUX_TEST_RESULT([if libcfs supports CPU hotplug state machine],
	[cpu_hotplug_state_machine], [
		AC_DEFINE(HAVE_HOTPLUG_STATE_MACHINE, 1,
			[hotplug state machine is supported])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_NODE_NR_WRITEBACK], [
	LB2_LINUX_TEST_SRC([node_nr_writeback_exists], [
	],[
		enum node_stat_item item = NR_WRITEBACK;
		(void)item;
	],[-Werror])
])
AC_DEFUN([LIBCFS_HAVE_NODE_NR_WRITEBACK], [
	LB2_MSG_LINUX_TEST_RESULT([if NR_WRITEBACK node_stat_item enum is available],
	[node_nr_writeback_exists], [
		AC_DEFINE(HAVE_NODE_NR_WRITEBACK, 1,
			[NR_WRITEBACK is moved into the node.])
	])
]) 
AC_DEFUN([LIBCFS_SRC_NLA_PUT_U64_64BIT], [
	LB2_LINUX_TEST_SRC([nla_put_u64_64bit], [
	],[
		nla_put_u64_64bit(NULL, 0, 0, 0)
	])
])
AC_DEFUN([LIBCFS_NLA_PUT_U64_64BIT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'nla_put_u64_64bit()' exists],
	[nla_put_u64_64bit], [
		AC_DEFINE(HAVE_NLA_PUT_U64_64BIT, 1,
			['nla_put_u64_64bit' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_SCHED_HEADERS], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/sched/signal.h], [-Werror])
])
AC_DEFUN([LIBCFS_SCHED_HEADERS], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/sched/signal.h], [
		AC_DEFINE(HAVE_SCHED_HEADERS, 1,
			[linux/sched header directory exist])
	])
]) 
AC_DEFUN([LIBCFS_SRC_KREF_READ], [
	LB2_LINUX_TEST_SRC([kref_read], [
	],[
		kref_read(NULL);
	])
])
AC_DEFUN([LIBCFS_KREF_READ], [
	LB2_MSG_LINUX_TEST_RESULT([if 'kref_read' exists],
	[kref_read], [
		AC_DEFINE(HAVE_KREF_READ, 1, [kref_read() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHT_BUCKET_VAR], [
	LB2_LINUX_TEST_SRC([rht_bucket_var], [
	],[
		rht_bucket_var(NULL, 0);
	])
])
AC_DEFUN([LIBCFS_RHT_BUCKET_VAR], [
	LB2_MSG_LINUX_TEST_RESULT([if 'rht_bucket_var' exists],
	[rht_bucket_var], [
		AC_DEFINE(HAVE_RHT_BUCKET_VAR, 1,
			[rht_bucket_var() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_NL_EXT_ACK], [
	LB2_LINUX_TEST_SRC([netlink_ext_ack], [
	],[
		struct genl_info info;
		info.extack = NULL;
	])
])
AC_DEFUN([LIBCFS_NL_EXT_ACK], [
	LB2_MSG_LINUX_TEST_RESULT([if Netlink supports netlink_ext_ack],
	[netlink_ext_ack], [
		AC_DEFINE(HAVE_NL_PARSE_WITH_EXT_ACK, 1,
			[netlink_ext_ack is an argument to nla_parse type function])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RHASHTABLE_LOOKUP_GET_INSERT_FAST], [
	LB2_LINUX_TEST_SRC([rhashtable_lookup_get_insert_fast], [
	],[
		const struct rhashtable_params params = { 0 };
		void *ret;
		ret = rhashtable_lookup_get_insert_fast(NULL, NULL, params);
	])
])
AC_DEFUN([LIBCFS_RHASHTABLE_LOOKUP_GET_INSERT_FAST], [
	LB2_MSG_LINUX_TEST_RESULT([if 'rhashtable_lookup_get_insert_fast' exist],
	[rhashtable_lookup_get_insert_fast], [
		AC_DEFINE(HAVE_RHASHTABLE_LOOKUP_GET_INSERT_FAST, 1,
			[rhashtable_lookup_get_insert_fast() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_CPUS_READ_LOCK], [
	LB2_LINUX_TEST_SRC([cpu_read_lock], [
	],[
		cpus_read_lock();
		cpus_read_unlock();
	])
])
AC_DEFUN([LIBCFS_CPUS_READ_LOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'cpus_read_[un]lock' exist],
	[cpu_read_lock], [
		AC_DEFINE(HAVE_CPUS_READ_LOCK, 1, ['cpus_read_lock' exist])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_WAIT_BIT_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/wait_bit.h], [-Werror])
])
AC_DEFUN([LIBCFS_HAVE_WAIT_BIT_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/wait_bit.h], [
		AC_DEFINE(HAVE_WAIT_BIT_HEADER_H, 1,
			[wait_bit.h is present])
	],[])
]) 
AC_DEFUN([LIBCFS_SRC_WAIT_QUEUE_TASK_LIST_RENAME], [
	LB2_LINUX_TEST_SRC([wait_queue_task_list], [
	],[
		wait_queue_head_t e;
		INIT_LIST_HEAD(&e.head);
	])
])
AC_DEFUN([LIBCFS_WAIT_QUEUE_TASK_LIST_RENAME], [
	LB2_MSG_LINUX_TEST_RESULT([if linux wait_queue_head list_head is named head],
	[wait_queue_task_list], [
		AC_DEFINE(HAVE_WAIT_QUEUE_ENTRY_LIST, 1,
			[linux wait_queue_head_t list_head is name head])
	])
]) 
AC_DEFUN([LIBCFS_SRC_WAIT_BIT_QUEUE_ENTRY_EXISTS], [
	LB2_LINUX_TEST_SRC([struct_wait_bit_queue_entry_exists], [
	],[
		struct wait_bit_queue_entry entry;
		memset(&entry, 0, sizeof(entry));
	])
])
AC_DEFUN([LIBCFS_WAIT_BIT_QUEUE_ENTRY_EXISTS], [
	LB2_MSG_LINUX_TEST_RESULT([if struct wait_bit_queue_entry exists],
	[struct_wait_bit_queue_entry_exists], [
		AC_DEFINE(HAVE_WAIT_BIT_QUEUE_ENTRY, 1,
			[if struct wait_bit_queue_entry exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_WAIT_QUEUE_ENTRY], [
	LB2_LINUX_TEST_SRC([wait_queue_entry], [
	],[
		wait_queue_entry_t e;
		e.flags = 0;
	])
])
AC_DEFUN([LIBCFS_WAIT_QUEUE_ENTRY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'wait_queue_entry_t' exists],
	[wait_queue_entry], [
		AC_DEFINE(HAVE_WAIT_QUEUE_ENTRY, 1,
			['wait_queue_entry_t' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_MM_TOTALRAM_PAGES_FUNC], [
	LB2_LINUX_TEST_SRC([totalram_pages], [
	],[
		totalram_pages_inc();
	],[-Werror])
])
AC_DEFUN([LIBCFS_MM_TOTALRAM_PAGES_FUNC], [
	LB2_MSG_LINUX_TEST_RESULT([if totalram_pages is a function],
	[totalram_pages], [
		AC_DEFINE(HAVE_TOTALRAM_PAGES_AS_FUNC, 1,
			[if totalram_pages is a function])
	])
]) 
AC_DEFUN([LIBCFS_SRC_DEFINE_TIMER], [
	LB2_LINUX_TEST_SRC([define_timer], [
	],[
		static DEFINE_TIMER(my_timer, NULL);
	])
])
AC_DEFUN([LIBCFS_DEFINE_TIMER], [
	LB2_MSG_LINUX_TEST_RESULT([if DEFINE_TIMER takes only 2 arguments],
	[define_timer], [
		AC_DEFINE(HAVE_NEW_DEFINE_TIMER, 1,
			[DEFINE_TIMER uses only 2 arguements])
	])
]) 
AC_DEFUN([LIBCFS_SRC_LOCKDEP_IS_HELD], [
	LB2_LINUX_TEST_SRC([lockdep_is_held], [
	],[
		const struct spinlock *lock = NULL;
		lockdep_is_held(lock);
	],[-Werror])
])
AC_DEFUN([LIBCFS_LOCKDEP_IS_HELD], [
	LB2_MSG_LINUX_TEST_RESULT([if 'lockdep_is_held()' uses const argument],
	[lockdep_is_held], [
	],[
		AC_DEFINE(NEED_LOCKDEP_IS_HELD_DISCARD_CONST, 1,
			[lockdep_is_held() argument is const])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TIMER_SETUP], [
	LB2_LINUX_TEST_SRC([timer_setup], [
	],[
		timer_setup(NULL, NULL, 0);
	])
])
AC_DEFUN([LIBCFS_TIMER_SETUP], [
	LB2_MSG_LINUX_TEST_RESULT([if setup_timer has been replaced with timer_setup],
	[timer_setup], [
		AC_DEFINE(HAVE_TIMER_SETUP, 1,
			[timer_setup has replaced setup_timer])
	])
]) 
AC_DEFUN([LIBCFS_SRC_WAIT_VAR_EVENT], [
	if test "x$lb_cv_header_linux_wait_bit_h" = xyes; then
		WAIT_BIT_H="-DHAVE_WAIT_BIT_HEADER_H=1"
	else
		WAIT_BIT_H=""
	fi
	LB2_LINUX_TEST_SRC([wait_var_event], [
	],[
		wake_up_var(NULL);
	],[${WAIT_BIT_H}])
])
AC_DEFUN([LIBCFS_WAIT_VAR_EVENT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'wait_var_event' exist],
	[wait_var_event], [
		AC_DEFINE(HAVE_WAIT_VAR_EVENT, 1,
			['wait_var_event' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_BITMAP_ALLOC], [
	LB2_LINUX_TEST_SRC([bitmap_alloc], [
	],[
		unsigned long *map = bitmap_alloc(1, GFP_KERNEL);
		(void)map;
	])
])
AC_DEFUN([LIBCFS_BITMAP_ALLOC], [
	LB2_MSG_LINUX_TEST_RESULT([if Linux bitmap memory management exist],
	[bitmap_alloc], [
		AC_DEFINE(HAVE_BITMAP_ALLOC, 1,
			[Linux bitmap can be allocated])
	])
]) 
AC_DEFUN([LIBCFS_SRC_CLEAR_AND_WAKE_UP_BIT], [
	if test "x$lb_cv_header_linux_wait_bit_h" = xyes; then
		WAIT_BIT_H="-DHAVE_WAIT_BIT_HEADER_H=1"
	else
		WAIT_BIT_H=""
	fi
	LB2_LINUX_TEST_SRC([clear_and_wake_up_bit], [
	],[
		clear_and_wake_up_bit(0, NULL);
	],[${WAIT_BIT_H}])
])
AC_DEFUN([LIBCFS_CLEAR_AND_WAKE_UP_BIT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'clear_and_wake_up_bit' exist],
	[clear_and_wake_up_bit], [
		AC_DEFINE(HAVE_CLEAR_AND_WAKE_UP_BIT, 1,
			['clear_and_wake_up_bit' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TCP_SOCK_SET_NODELAY], [
	LB2_LINUX_TEST_SRC([tcp_sock_set_nodelay_exists], [
	],[
		tcp_sock_set_nodelay(NULL);
	],[-Werror])
])
AC_DEFUN([LIBCFS_TCP_SOCK_SET_NODELAY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'tcp_sock_set_nodelay()' exists],
	[tcp_sock_set_nodelay_exists], [
		AC_DEFINE(HAVE_TCP_SOCK_SET_NODELAY, 1,
			['tcp_sock_set_nodelay()' exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TCP_SOCK_SET_KEEPIDLE], [
	LB2_LINUX_TEST_SRC([tcp_sock_set_keepidle_exists], [
	],[
		tcp_sock_set_keepidle(NULL, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_TCP_SOCK_SET_KEEPIDLE], [
	LB2_MSG_LINUX_TEST_RESULT([if 'tcp_sock_set_keepidle()' exists],
	[tcp_sock_set_keepidle_exists], [
		AC_DEFINE(HAVE_TCP_SOCK_SET_KEEPIDLE, 1,
			['tcp_sock_set_keepidle()' exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TCP_SOCK_SET_QUICKACK], [
	LB2_LINUX_TEST_SRC([tcp_sock_set_quickack_exists], [
	],[
		tcp_sock_set_quickack(NULL, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_TCP_SOCK_SET_QUICKACK], [
	LB2_MSG_LINUX_TEST_RESULT([if 'tcp_sock_set_quickack()' exists],
	[tcp_sock_set_quickack_exists], [
		AC_DEFINE(HAVE_TCP_SOCK_SET_QUICKACK, 1,
			['tcp_sock_set_quickack()' exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TCP_SOCK_SET_KEEPINTVL], [
	LB2_LINUX_TEST_SRC([tcp_sock_set_keepintvl_exists], [
	],[
		tcp_sock_set_keepintvl(NULL, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_TCP_SOCK_SET_KEEPINTVL], [
	LB2_MSG_LINUX_TEST_RESULT([if 'tcp_sock_set_keepintvl()' exists],
	[tcp_sock_set_keepintvl_exists], [
		AC_DEFINE(HAVE_TCP_SOCK_SET_KEEPINTVL, 1,
			['tcp_sock_set_keepintvl()' exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TCP_SOCK_SET_KEEPCNT], [
	LB2_LINUX_TEST_SRC([tcp_sock_set_keepcnt_exists], [
	],[
		tcp_sock_set_keepcnt(NULL, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_TCP_SOCK_SET_KEEPCNT], [
	LB2_MSG_LINUX_TEST_RESULT([if 'tcp_sock_set_keepcnt()' exists],
	[tcp_sock_set_keepcnt_exists], [
		AC_DEFINE(HAVE_TCP_SOCK_SET_KEEPCNT, 1,
			['tcp_sock_set_keepcnt()' exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_NL_DUMP_EXT_ACK], [
	LB2_LINUX_TEST_SRC([netlink_dump_ext_ack], [
	],[
		struct netlink_callback *cb = NULL;
		cb->extack = NULL;
	],[])
])
AC_DEFUN([LIBCFS_NL_DUMP_EXT_ACK], [
	LB2_MSG_LINUX_TEST_RESULT([if Netlink dump handlers support ext_ack],
	[netlink_dump_ext_ack], [
		AC_DEFINE(HAVE_NL_DUMP_WITH_EXT_ACK, 1,
			[netlink_ext_ack is handled for Netlink dump handlers])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_IOV_ITER_TYPE], [
	LB2_LINUX_TEST_SRC([macro_iov_iter_type_exists], [
	],[
		struct iov_iter iter = { };
		enum iter_type type = iov_iter_type(&iter);
		(void)type;
	],[-Werror])
])
AC_DEFUN([LIBCFS_HAVE_IOV_ITER_TYPE], [
	LB2_MSG_LINUX_TEST_RESULT([if iov_iter_type exists],
	[macro_iov_iter_type_exists], [
		AC_DEFINE(HAVE_IOV_ITER_TYPE, 1,
			[if iov_iter_type exists])
	])
]) 
AC_DEFUN([LIBCFS_GENRADIX], [
LB_CHECK_EXPORT([__genradix_ptr], [lib/generic-radix-tree.c],
	[AC_DEFINE(HAVE_GENRADIX_SUPPORT, 1,
		[generic-radix-tree is present])])
]) 
AC_DEFUN([LIBCFS_SRC_GET_REQUEST_KEY_AUTH], [
	LB2_LINUX_TEST_SRC([get_request_key_auth_exported], [
	],[
		struct key *ring;
		const struct key *key = NULL;
		struct request_key_auth *rka = get_request_key_auth(key);
		ring = key_get(rka->dest_keyring);
	],[-Werror])
])
AC_DEFUN([LIBCFS_GET_REQUEST_KEY_AUTH], [
	LB2_MSG_LINUX_TEST_RESULT([if get_request_key_auth() is available],
	[get_request_key_auth_exported], [
		AC_DEFINE(HAVE_GET_REQUEST_KEY_AUTH, 1,
			[get_request_key_auth() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_KOBJ_TYPE_DEFAULT_GROUPS],[
	LB2_LINUX_TEST_SRC([kobj_type_default_groups], [
	],[
		struct kobj_type *kobj_type = NULL;
		void *has = kobj_type->default_groups;
		(void) has;
	])
])
AC_DEFUN([LIBCFS_KOBJ_TYPE_DEFAULT_GROUPS],[
	LB2_MSG_LINUX_TEST_RESULT([if struct kobj_type have 'default_groups' member],
	[kobj_type_default_groups], [
		AC_DEFINE(HAVE_KOBJ_TYPE_DEFAULT_GROUPS, 1,
			[struct kobj_type has 'default_groups' member])
	])
]) 
AC_DEFUN([LIBCFS_SRC_LOOKUP_USER_KEY], [
	LB2_LINUX_TEST_SRC([lookup_user_key_exported], [
	],[
		lookup_user_key(KEY_SPEC_USER_KEYRING, 0, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_LOOKUP_USER_KEY], [
	LB2_MSG_LINUX_TEST_RESULT([if lookup_user_key() is available],
	[lookup_user_key_exported], [
		AC_DEFINE(HAVE_LOOKUP_USER_KEY, 1,
			[lookup_user_key() is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_CACHE_DETAIL_WRITERS], [
	LB2_LINUX_TEST_SRC([cache_detail_writers_atomic], [
		static struct cache_detail rsi_cache;
	],[
		atomic_set(&rsi_cache.writers, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_CACHE_DETAIL_WRITERS], [
	LB2_MSG_LINUX_TEST_RESULT([if struct cache_detail has writers],
	[cache_detail_writers_atomic], [
		AC_DEFINE(HAVE_CACHE_DETAIL_WRITERS, 1,
			[struct cache_detail has writers])
	])
]) 
AC_DEFUN([LIBCFS_SRC_GENL_DUMPIT_INFO], [
	LB2_LINUX_TEST_SRC([genl_dumpit_info], [
	],[
		static struct genl_dumpit_info info;
		info.family = NULL;
	],[-Werror])
])
AC_DEFUN([LIBCFS_GENL_DUMPIT_INFO], [
	LB2_MSG_LINUX_TEST_RESULT([if struct genl_dumpit_info has family field],
	[genl_dumpit_info], [
		AC_DEFINE(HAVE_GENL_DUMPIT_INFO, 1,
			[struct genl_dumpit_info has family field])
	])
]) 
AC_DEFUN([LIBCFS_KALLSYMS_LOOKUP], [
LB_CHECK_EXPORT([kallsyms_lookup_name], [kernel/kallsyms.c],
	[AC_DEFINE(HAVE_KALLSYMS_LOOKUP_NAME, 1,
		[kallsyms_lookup_name is exported by kernel])])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_PROC_OPS], [
	LB2_LINUX_TEST_SRC([proc_ops], [
		static struct proc_ops *my_proc;
	],[
		my_proc->proc_lseek = NULL;
	],[-Werror])
]) 
AC_DEFUN([LIBCFS_HAVE_PROC_OPS], [
	LB2_MSG_LINUX_TEST_RESULT([if struct proc_ops exists],
	[proc_ops], [
		AC_DEFINE(HAVE_PROC_OPS, 1,
			[struct proc_ops exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_IP6_SET_PREF], [
	LB2_LINUX_TEST_SRC([ip6_set_pref_test], [
	],[
		ip6_sock_set_addr_preferences(NULL, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_IP6_SET_PREF], [
	LB2_MSG_LINUX_TEST_RESULT([if ip6_sock_set_addr_preferences() exists],
	[ip6_set_pref_test], [
		AC_DEFINE(HAVE_IP6_SET_PREF, 1,
			[if ip6_sock_set_addr_preferences exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_IP_SET_TOS], [
	LB2_LINUX_TEST_SRC([ip_set_tos_test], [
	],[
		ip_sock_set_tos(NULL, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_IP_SET_TOS], [
	LB2_MSG_LINUX_TEST_RESULT([if ip_sock_set_tos() exists],
	[ip_set_tos_test], [
		AC_DEFINE(HAVE_IP_SET_TOS, 1,
			[if ip_sock_set_tos exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_VMALLOC_2ARGS], [
	LB2_LINUX_TEST_SRC([vmalloc_2args], [
	],[
		__vmalloc(0, 0);
	],[])
])
AC_DEFUN([LIBCFS_VMALLOC_2ARGS], [
	LB2_MSG_LINUX_TEST_RESULT([if __vmalloc has 2 args],
	[vmalloc_2args], [
		AC_DEFINE(HAVE_VMALLOC_2ARGS, 1,
			[__vmalloc only takes 2 args.])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_NR_UNSTABLE_NFS], [
	LB2_LINUX_TEST_SRC([nr_unstable_nfs_exists], [
		int i;
	],[
		i = NR_UNSTABLE_NFS;
	],[-Werror])
])
AC_DEFUN([LIBCFS_HAVE_NR_UNSTABLE_NFS], [
	LB2_MSG_LINUX_TEST_RESULT([if NR_UNSTABLE_NFS still in use],
	[nr_unstable_nfs_exists], [
		AC_DEFINE(HAVE_NR_UNSTABLE_NFS, 1,
			[NR_UNSTABLE_NFS is still in use.])
	])
]) 
AC_DEFUN([LIBCFS_NR_UNSTABLE_NFS_DEPRECATED], [
	AC_MSG_CHECKING([if NR_UNSTABLE_NFS is defined but DEPRECATED])
	AS_IF([grep -q -E "NFS unstable pages - DEPRECATED DO NOT USE" "$LINUX/include/linux/mmzone.h" 2>/dev/null], [
		AC_DEFINE([HAVE_NR_UNSTABLE_NFS_DEPRECATED], 1,
			  [NR_UNSTABLE_NFS is defined but deprecated])
		AC_MSG_RESULT(yes)
	],[
		AC_MSG_RESULT(no)
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_MMAP_LOCK], [
	LB2_LINUX_TEST_SRC([mmap_write_lock], [
	],[
		mmap_write_lock(NULL);
	],[])
])
AC_DEFUN([LIBCFS_HAVE_MMAP_LOCK], [
	LB2_MSG_LINUX_TEST_RESULT([if mmap_lock API is available],
	[mmap_write_lock], [
		AC_DEFINE(HAVE_MMAP_LOCK, 1,
			[mmap_lock API is available.])
	])
]) 
AC_DEFUN([LIBCFS_SRC_KERNEL_SETSOCKOPT], [
	LB2_LINUX_TEST_SRC([kernel_setsockopt_exists], [
	],[
		kernel_setsockopt(NULL, 0, 0, NULL, 0);
	],[-Werror])
])
AC_DEFUN([LIBCFS_KERNEL_SETSOCKOPT], [
	LB2_MSG_LINUX_TEST_RESULT([if kernel_setsockopt still in use],
	[kernel_setsockopt_exists], [
	AC_DEFINE(HAVE_KERNEL_SETSOCKOPT, 1,
		[kernel_setsockopt still in use])
	])
]) 
AC_DEFUN([LIBCFS_SRC_USER_UID_KEYRING], [
	LB2_LINUX_TEST_SRC([user_uid_keyring_exists], [
	],[
		((struct user_struct *)0)->uid_keyring = NULL;
	],[-Werror])
])
AC_DEFUN([LIBCFS_USER_UID_KEYRING], [
	AC_MSG_CHECKING([if uid_keyring exists])
	LB2_LINUX_TEST_RESULT([user_uid_keyring_exists], [
		AC_DEFINE(HAVE_USER_UID_KEYRING, 1,
			[uid_keyring exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_KEY_NEED_UNLINK], [
	LB2_LINUX_TEST_SRC([key_need_unlink_exists], [
	],[
		lookup_user_key(0, 0, KEY_NEED_UNLINK);
	],[-Werror])
])
AC_DEFUN([LIBCFS_KEY_NEED_UNLINK], [
	LB2_MSG_LINUX_TEST_RESULT([if KEY_NEED_UNLINK exists],
	[key_need_unlink_exists], [
		AC_DEFINE(HAVE_KEY_NEED_UNLINK, 1,
			[KEY_NEED_UNLINK exists])
	])
]) 
AC_DEFUN([LIBCFS_SRC_SEC_RELEASE_SECCTX], [
	LB2_LINUX_TEST_SRC([security_release_secctx_1arg], [
	],[
		security_release_secctx(NULL);
	],[])
])
AC_DEFUN([LIBCFS_SEC_RELEASE_SECCTX], [
	LB2_MSG_LINUX_TEST_RESULT([if security_release_secctx has 1 arg],
	[security_release_secctx_1arg], [
		AC_DEFINE(HAVE_SEC_RELEASE_SECCTX_1ARG, 1,
			[security_release_secctx has 1 arg.])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_KMAP_LOCAL], [
	LB2_LINUX_TEST_SRC([kmap_local_page], [
	],[
		struct page *pg = NULL;
		void *kaddr = kmap_local_page(pg);
		kunmap_local(kaddr);
	],[-Werror])
])
AC_DEFUN([LIBCFS_HAVE_KMAP_LOCAL], [
	LB2_MSG_LINUX_TEST_RESULT([if 'kmap_local*' are available],
	[kmap_local_page], [
		AC_DEFINE(HAVE_KMAP_LOCAL, 1,
			[kmap_local_* functions are available])
	],[
		AC_DEFINE([kmap_local_page(p)], [kmap_atomic(p)],
			  [need kmap_local_page map to atomic])
		AC_DEFINE([kunmap_local(kaddr)], [kunmap_atomic((kaddr))],
			  [need kunmap_local map to atomic])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_KFREE_SENSITIVE], [
	LB2_LINUX_TEST_SRC([kfree_sensitive_exists], [
	],[
		kfree_sensitive(NULL);
	], [-Werror])
])
AC_DEFUN([LIBCFS_HAVE_KFREE_SENSITIVE], [
	LB2_MSG_LINUX_TEST_RESULT([if kfree_sensitive() is available],
	[kfree_sensitive_exists], [
		AC_DEFINE(HAVE_KFREE_SENSITIVE, 1,
			[kfree_sensitive() is available.])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_CRYPTO_SHA2_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([crypto/sha2.h], [-Werror])
])
AC_DEFUN([LIBCFS_HAVE_CRYPTO_SHA2_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([crypto/sha2.h], [
		AC_DEFINE(HAVE_CRYPTO_SHA2_HEADER, 1,
			[crypto/sha2.h is present])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_LIST_CMP_FUNC_T], [
	LB2_LINUX_TEST_SRC([list_cmp_func_t_exists], [
	],[
		list_cmp_func_t cmp;
		(void)cmp;
	], [-Werror])
])
AC_DEFUN([LIBCFS_HAVE_LIST_CMP_FUNC_T], [
	LB2_MSG_LINUX_TEST_RESULT([if list_cmp_func_t type is defined],
	[list_cmp_func_t_exists], [
		AC_DEFINE(HAVE_LIST_CMP_FUNC_T, 1,
			[list_cmp_func_t type is defined])
	])
]) 
AC_DEFUN([LIBCFS_SRC_NLA_STRLCPY], [
	LB2_LINUX_TEST_SRC([nla_strlcpy], [
	],[
		if (nla_strlcpy(NULL, NULL, 0) == 0)
			return -EINVAL;
	])
])
AC_DEFUN([LIBCFS_NLA_STRLCPY], [
	LB2_MSG_LINUX_TEST_RESULT([if 'nla_strlcpy()' still exists],
	[nla_strlcpy], [
		AC_DEFINE(HAVE_NLA_STRLCPY, 1,
			['nla_strlcpy' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_RB_FIND], [
	LB2_LINUX_TEST_SRC([rb_find], [
		static int cmp(const void *key, const struct rb_node *node)
		{
			return 0;
		}
	],[
		void *key = NULL;
		struct rb_root *tree = NULL;
		struct rb_node *node __maybe_unused = rb_find(key, tree, cmp);
	])
])
AC_DEFUN([LIBCFS_RB_FIND], [
	LB2_MSG_LINUX_TEST_RESULT([if 'rb_find()' is available],
	[rb_find], [
		AC_DEFINE(HAVE_RB_FIND, 1,
			['rb_find()' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_LINUX_FORTIFY_STRING_HEADER],[
	LB2_LINUX_TEST_SRC([linux_fortify_string_header], [
	],[
	],[])
])
AC_DEFUN([LIBCFS_LINUX_FORTIFY_STRING_HEADER],[
	LB2_MSG_LINUX_TEST_RESULT([if linux/fortify-string.h header available],
	[linux_fortify_string_header], [
		AC_DEFINE(HAVE_LINUX_FORTIFY_STRING_HEADER, 1,
			[linux/fortify-string.h header available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_CIPHER_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([crypto/internal/cipher.h], [-Werror])
])
AC_DEFUN([LIBCFS_HAVE_CIPHER_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([crypto/internal/cipher.h], [
		AC_DEFINE(HAVE_CIPHER_H, 1,
			[crypto/internal/cipher.h is present])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_TASK_IS_RUNNING], [
	LB2_LINUX_TEST_SRC([task_is_running], [
	],[
		if (task_is_running(current))
			schedule();
	], [-Werror])
])
AC_DEFUN([LIBCFS_HAVE_TASK_IS_RUNNING], [
	LB2_MSG_LINUX_TEST_RESULT([if task_is_running() is defined],
	[task_is_running], [
		AC_DEFINE(HAVE_TASK_IS_RUNNING, 1,
			[task_is_running() is defined])
	])
]) 
AC_DEFUN([LIBCFS_SRC_LINUX_STDARG_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/stdarg.h], [-Werror])
])
AC_DEFUN([LIBCFS_LINUX_STDARG_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/stdarg.h], [
		AC_DEFINE(HAVE_LINUX_STDARG_HEADER, 1,
			[linux/stdarg.h is present])
	])
]) 
AC_DEFUN([LIBCFS_SRC_HAVE_PANIC_NOTIFIER_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/panic_notifier.h], [-Werror])
])
AC_DEFUN([LIBCFS_HAVE_PANIC_NOTIFIER_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/panic_notifier.h], [
		AC_DEFINE(HAVE_PANIC_NOTIFIER_H, 1,
			[linux/panic_notifier.h is present])
	])
]) 
AC_DEFUN([LIBCFS_SRC_PARAM_SET_UINT_MINMAX],[
	LB2_LINUX_TEST_SRC([param_set_uint_minmax], [
	],[
		param_set_uint_minmax(NULL, NULL, 0, 0);
	], [])
])
AC_DEFUN([LIBCFS_PARAM_SET_UINT_MINMAX],[
	LB2_MSG_LINUX_TEST_RESULT([if function 'param_set_uint_minmax' exist],
	[param_set_uint_minmax], [
		AC_DEFINE(HAVE_PARAM_SET_UINT_MINMAX, 1,
			['param_set_uint_minmax' is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_LINUX_BLK_INTEGRITY_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/blk-integrity.h], [-Werror])
])
AC_DEFUN([LIBCFS_LINUX_BLK_INTEGRITY_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/blk-integrity.h], [
		AC_DEFINE(HAVE_LINUX_BLK_INTEGRITY_HEADER, 1,
			[linux/blk-integrity.h is present])
	])
]) 
AC_DEFUN([LIBCFS_SRC_PDE_DATA_EXISTS],[
	LB2_LINUX_TEST_SRC([pde_data], [
	],[
		struct inode *inode = NULL;
		void *data =pde_data(inode);
		(void)data;
	],[])
])
AC_DEFUN([LIBCFS_PDE_DATA_EXISTS],[
	LB2_MSG_LINUX_TEST_RESULT([if function 'pde_data' exist],
	[pde_data], [
		AC_DEFINE(HAVE_pde_data, 1, [function pde_data() available])
	],[
		AC_DEFINE(pde_data(inode), PDE_DATA(inode),
			  [function pde_data() unavailable])
	])
]) 
AC_DEFUN([LIBCFS_SRC_BIO_ALLOC_WITH_BDEV],[
	LB2_LINUX_TEST_SRC([bio_alloc_with_bdev], [
	],[
		struct block_device *bdev = NULL;
		unsigned short nr_vecs = 1;
		gfp_t gfp = GFP_KERNEL;
		struct bio *bio = bio_alloc(bdev, nr_vecs, REQ_OP_WRITE, gfp);
		(void) bio;
	],[])
])
AC_DEFUN([LIBCFS_BIO_ALLOC_WITH_BDEV],[
	LB2_MSG_LINUX_TEST_RESULT([if bio_alloc() takes a struct block_device],
	[bio_alloc_with_bdev], [
		AC_DEFINE(HAVE_BIO_ALLOC_WITH_BDEV, 1,
			[bio_alloc() takes a struct block_device])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TIMER_DELETE_SYNC],[
	LB2_LINUX_TEST_SRC([timer_delete_sync], [
	],[
		struct timer_list *timer = NULL;
		(void)timer_delete_sync(timer);
	],[])
])
AC_DEFUN([LIBCFS_TIMER_DELETE_SYNC],[
	LB2_MSG_LINUX_TEST_RESULT([if timer_delete_sync() is available],
	[timer_delete_sync], [
		AC_DEFINE(HAVE_TIMER_DELETE_SYNC, 1,
			[timer_delete_sync() is available])
	],[
		AC_DEFINE(timer_delete_sync(t), del_timer_sync(t),
			[timer_delete_sync() not is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_TIMER_DELETE],[
	LB2_LINUX_TEST_SRC([timer_delete], [
	],[
		struct timer_list *timer = NULL;
		(void)timer_delete(timer);
	],[])
])
AC_DEFUN([LIBCFS_TIMER_DELETE],[
	LB2_MSG_LINUX_TEST_RESULT([if timer_delete() is available],
	[timer_delete], [
		AC_DEFINE(HAVE_TIMER_DELETE, 1,
			[timer_delete() is available])
	],[
		AC_DEFINE(timer_delete(t), del_timer(t),
			[timer_delete() not is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_CONSTIFY_CTR_TABLE],[
	LB2_LINUX_TEST_SRC([constify_struct_ctl_table], [
		static int handler(const struct ctl_table *table, int write,
				   void __user *buf, size_t *lenp, loff_t *ppos)
		{
			return 0;
		}
	],[
		static struct ctl_table ctl_tbl __attribute__ ((unused)) = {
			.proc_handler	= &handler,
		};
	],[-Werror])
])
AC_DEFUN([LIBCFS_CONSTIFY_CTR_TABLE],[
	LB2_MSG_LINUX_TEST_RESULT(
	[if struct ctl_table argument to proc_handler() is const],
	[constify_struct_ctl_table], [
		AC_DEFINE(HAVE_CONST_CTR_TABLE, 1,
			[struct ctl_table argument to proc_handler() is const])
	])
]) 
AC_DEFUN([LIBCFS_SRC_BLK_INTEGRITY_NOVERIFY], [
	LB2_LINUX_TEST_SRC([blk_integrity_noverify], [
	],[
		int flag __attribute__ ((unused)) = BLK_INTEGRITY_NOVERIFY;
	],[-Werror])
])
AC_DEFUN([LIBCFS_BLK_INTEGRITY_NOVERIFY], [
	LB2_MSG_LINUX_TEST_RESULT([if BLK_INTEGRITY_NOVERIFY is available],
	[blk_integrity_noverify], [
		AC_DEFINE(HAVE_BLK_INTEGRITY_NOVERIFY, 1,
			[BLK_INTEGRITY_NOVERIFY is available])
	])
]) 
AC_DEFUN([LIBCFS_SRC_LINUX_BIO_INTEGRITY_HEADER], [
	LB2_CHECK_LINUX_HEADER_SRC([linux/bio-integrity.h], [-Werror])
])
AC_DEFUN([LIBCFS_LINUX_BIO_INTEGRITY_HEADER], [
	LB2_CHECK_LINUX_HEADER_RESULT([linux/bio-integrity.h], [
		AC_DEFINE(HAVE_LINUX_BIO_INTEGRITY_HEADER, 1,
			[linux/bio-integrity.h is present])
	])
]) 
AC_DEFUN([LIBCFS_PROG_LINUX_SRC], [
	LIBCFS_SRC_PREPARE_TO_WAIT_EVENT
	LIBCFS_SRC_KERNEL_PARAM_OPS
	LIBCFS_SRC_HAVE_MAPPING_AS_EXITING_FLAG
	LIBCFS_SRC_IOV_ITER_HAS_TYPE
	LIBCFS_SRC_HAVE_GLOB
	LIBCFS_SRC_WAIT_WOKEN
	LIBCFS_SRC_KERNEL_PARAM_LOCK
	LIBCFS_SRC_STRSCPY_EXISTS
	LIBCFS_SRC_HAVE_TOPOLOGY_SIBLING_CPUMASK
	LIBCFS_SRC_NETLINK_CALLBACK_START
	LIBCFS_SRC_CRYPTO_HASH_HELPERS
	LIBCFS_SRC_RHASHTABLE_REPLACE
	LIBCFS_SRC_BROKEN_HASH_64
	LIBCFS_SRC_GET_USER_PAGES_6ARG
	LIBCFS_SRC_STRINGHASH
	LIBCFS_SRC_RHASHTABLE_INSERT_FAST
	LIBCFS_SRC_RHASHTABLE_WALK_INIT_3ARG
	LIBCFS_SRC_RHASHTABLE_LOOKUP
	LIBCFS_SRC_RHLTABLE
	LIBCFS_SRC_GET_USER_PAGES_GUP_FLAGS
	LIBCFS_SRC_RHASHTABLE_WALK_ENTER
	LIBCFS_SRC_HOTPLUG_STATE_MACHINE
	LIBCFS_SRC_NLA_PUT_U64_64BIT
	LIBCFS_SRC_HAVE_NODE_NR_WRITEBACK
	LIBCFS_SRC_NL_EXT_ACK
	LIBCFS_SRC_RHASHTABLE_LOOKUP_GET_INSERT_FAST
	LIBCFS_SRC_SCHED_HEADERS
	LIBCFS_SRC_KREF_READ
	LIBCFS_SRC_RHT_BUCKET_VAR
	LIBCFS_SRC_CPUS_READ_LOCK
	LIBCFS_SRC_WAIT_QUEUE_TASK_LIST_RENAME
	LIBCFS_SRC_WAIT_BIT_QUEUE_ENTRY_EXISTS
	LIBCFS_SRC_WAIT_QUEUE_ENTRY
	LIBCFS_SRC_DEFINE_TIMER
	LIBCFS_SRC_TIMER_SETUP
	LIBCFS_SRC_WAIT_VAR_EVENT
	LIBCFS_SRC_BITMAP_ALLOC
	LIBCFS_SRC_CLEAR_AND_WAKE_UP_BIT
	LIBCFS_SRC_TCP_SOCK_SET_NODELAY
	LIBCFS_SRC_TCP_SOCK_SET_KEEPIDLE
	LIBCFS_SRC_NL_DUMP_EXT_ACK
	LIBCFS_SRC_HAVE_IOV_ITER_TYPE
	LIBCFS_SRC_MM_TOTALRAM_PAGES_FUNC
	LIBCFS_SRC_GET_REQUEST_KEY_AUTH
	LIBCFS_SRC_KOBJ_TYPE_DEFAULT_GROUPS
	LIBCFS_SRC_USER_UID_KEYRING
	LIBCFS_SRC_LOOKUP_USER_KEY
	LIBCFS_SRC_CACHE_DETAIL_WRITERS
	LIBCFS_SRC_GENL_DUMPIT_INFO
	LIBCFS_SRC_HAVE_PROC_OPS
	LIBCFS_SRC_TCP_SOCK_SET_QUICKACK
	LIBCFS_SRC_TCP_SOCK_SET_KEEPINTVL
	LIBCFS_SRC_TCP_SOCK_SET_KEEPCNT
	LIBCFS_SRC_IP6_SET_PREF
	LIBCFS_SRC_IP_SET_TOS
	LIBCFS_SRC_VMALLOC_2ARGS
	LIBCFS_SRC_HAVE_NR_UNSTABLE_NFS
	LIBCFS_SRC_KERNEL_SETSOCKOPT
	LIBCFS_SRC_KEY_NEED_UNLINK
	LIBCFS_SRC_SEC_RELEASE_SECCTX
	LIBCFS_SRC_HAVE_KMAP_LOCAL
	LIBCFS_SRC_HAVE_KFREE_SENSITIVE
	LIBCFS_SRC_HAVE_CRYPTO_SHA2_HEADER
	LIBCFS_SRC_HAVE_LIST_CMP_FUNC_T
	LIBCFS_SRC_NLA_STRLCPY
	LIBCFS_SRC_RB_FIND
	LIBCFS_SRC_LINUX_FORTIFY_STRING_HEADER
	LIBCFS_SRC_HAVE_CIPHER_HEADER
	LIBCFS_SRC_HAVE_TASK_IS_RUNNING
	LIBCFS_SRC_LINUX_STDARG_HEADER
	LIBCFS_SRC_HAVE_PANIC_NOTIFIER_HEADER
	LIBCFS_SRC_PARAM_SET_UINT_MINMAX
	LIBCFS_SRC_PDE_DATA_EXISTS
	LIBCFS_SRC_BIO_ALLOC_WITH_BDEV
	LIBCFS_SRC_TIMER_DELETE_SYNC
	LIBCFS_SRC_TIMER_DELETE
	LIBCFS_SRC_CONSTIFY_CTR_TABLE
	LIBCFS_SRC_BLK_INTEGRITY_NOVERIFY
])
AC_DEFUN([LIBCFS_PROG_LINUX_RESULTS], [
	LIBCFS_PREPARE_TO_WAIT_EVENT
	LIBCFS_KERNEL_PARAM_OPS
	LIBCFS_HAVE_MAPPING_AS_EXITING_FLAG
	LIBCFS_IOV_ITER_HAS_TYPE
	LIBCFS_HAVE_GLOB
	LIBCFS_WAIT_WOKEN
	LIBCFS_KERNEL_PARAM_LOCK
	LIBCFS_STRSCPY_EXISTS
	LIBCFS_HAVE_TOPOLOGY_SIBLING_CPUMASK
	LIBCFS_NETLINK_CALLBACK_START
	LIBCFS_CRYPTO_HASH_HELPERS
	LIBCFS_RHASHTABLE_REPLACE
	LIBCFS_BROKEN_HASH_64
	LIBCFS_GET_USER_PAGES_6ARG
	LIBCFS_STRINGHASH
	LIBCFS_RHASHTABLE_INSERT_FAST
	LIBCFS_RHASHTABLE_WALK_INIT_3ARG
	LIBCFS_RHASHTABLE_LOOKUP
	LIBCFS_RHLTABLE
	LIBCFS_GET_USER_PAGES_GUP_FLAGS
	LIBCFS_RHASHTABLE_WALK_ENTER
	LIBCFS_HOTPLUG_STATE_MACHINE
	LIBCFS_NLA_PUT_U64_64BIT
	LIBCFS_HAVE_NODE_NR_WRITEBACK
	LIBCFS_NL_EXT_ACK
	LIBCFS_RHASHTABLE_LOOKUP_GET_INSERT_FAST
	LIBCFS_SCHED_HEADERS
	LIBCFS_KREF_READ
	LIBCFS_RHT_BUCKET_VAR
	LIBCFS_CPUS_READ_LOCK
	LIBCFS_WAIT_QUEUE_TASK_LIST_RENAME
	LIBCFS_WAIT_BIT_QUEUE_ENTRY_EXISTS
	LIBCFS_WAIT_QUEUE_ENTRY
	LIBCFS_DEFINE_TIMER
	LIBCFS_TIMER_SETUP
	LIBCFS_WAIT_VAR_EVENT
	LIBCFS_BITMAP_ALLOC
	LIBCFS_CLEAR_AND_WAKE_UP_BIT
	LIBCFS_TCP_SOCK_SET_NODELAY
	LIBCFS_TCP_SOCK_SET_KEEPIDLE
	LIBCFS_NL_DUMP_EXT_ACK
	LIBCFS_HAVE_IOV_ITER_TYPE
	LIBCFS_MM_TOTALRAM_PAGES_FUNC
	LIBCFS_GET_REQUEST_KEY_AUTH
	LIBCFS_KOBJ_TYPE_DEFAULT_GROUPS
	LIBCFS_USER_UID_KEYRING
	LIBCFS_LOOKUP_USER_KEY
	LIBCFS_CACHE_DETAIL_WRITERS
	LIBCFS_GENL_DUMPIT_INFO
	LIBCFS_HAVE_PROC_OPS
	LIBCFS_TCP_SOCK_SET_QUICKACK
	LIBCFS_TCP_SOCK_SET_KEEPINTVL
	LIBCFS_TCP_SOCK_SET_KEEPCNT
	LIBCFS_IP6_SET_PREF
	LIBCFS_IP_SET_TOS
	LIBCFS_VMALLOC_2ARGS
	LIBCFS_HAVE_NR_UNSTABLE_NFS
	LIBCFS_NR_UNSTABLE_NFS_DEPRECATED
	LIBCFS_KERNEL_SETSOCKOPT
	LIBCFS_KEY_NEED_UNLINK
	LIBCFS_SEC_RELEASE_SECCTX
	LIBCFS_HAVE_KMAP_LOCAL
	LIBCFS_HAVE_KFREE_SENSITIVE
	LIBCFS_HAVE_CRYPTO_SHA2_HEADER
	LIBCFS_HAVE_LIST_CMP_FUNC_T
	LIBCFS_NLA_STRLCPY
	LIBCFS_RB_FIND
	LIBCFS_LINUX_FORTIFY_STRING_HEADER
	LIBCFS_HAVE_CIPHER_HEADER
	LIBCFS_HAVE_TASK_IS_RUNNING
	LIBCFS_LINUX_STDARG_HEADER
	LIBCFS_HAVE_PANIC_NOTIFIER_HEADER
	LIBCFS_PARAM_SET_UINT_MINMAX
	LIBCFS_PDE_DATA_EXISTS
	LIBCFS_BIO_ALLOC_WITH_BDEV
	LIBCFS_TIMER_DELETE_SYNC
	LIBCFS_TIMER_DELETE
	LIBCFS_CONSTIFY_CTR_TABLE
	LIBCFS_BLK_INTEGRITY_NOVERIFY
])
AC_DEFUN([LIBCFS_PROG_LINUX], [
AC_MSG_NOTICE([LibCFS kernel checks
==============================================================================])
LIBCFS_CONFIG_PANIC_DUMPLOG
LIBCFS_GENRADIX
LIBCFS_KALLSYMS_LOOKUP
]) 
AC_DEFUN([LIBCFS_PATH_DEFAULTS], [
]) 
AC_DEFUN([LIBCFS_CONFIGURE], [
AC_MSG_NOTICE([LibCFS core checks
==============================================================================])
AC_CHECK_HEADERS([netdb.h asm/types.h endian.h])
AC_MSG_NOTICE([LibCFS required packages checks
==============================================================================])
AC_MSG_CHECKING([whether to enable readline support])
AC_ARG_ENABLE(readline,
	AS_HELP_STRING([--disable-readline],
		[disable readline support]),
	[], [enable_readline="yes"])
AC_MSG_RESULT([$enable_readline])
LIBREADLINE=""
AS_IF([test "x$enable_readline" = xyes], [
	AC_CHECK_LIB([readline], [readline], [
		LIBREADLINE="-lreadline"
		AC_DEFINE(HAVE_LIBREADLINE, 1,
			[readline library is available])
	])
	AC_SUBST(ENABLE_READLINE, yes)
], [
	AC_SUBST(ENABLE_READLINE, no)
])
AC_SUBST(LIBREADLINE)
AC_MSG_CHECKING([whether to use libpthread for libcfs library])
AC_ARG_ENABLE([libpthread],
	AS_HELP_STRING([--disable-libpthread],
		[disable libpthread]),
	[], [enable_libpthread="yes"])
AC_MSG_RESULT([$enable_libpthread])
PTHREAD_LIBS=""
AS_IF([test "x$enable_libpthread" = xyes], [
	AC_CHECK_LIB([pthread], [pthread_create], [
		PTHREAD_LIBS="-lpthread"
		AC_DEFINE([HAVE_LIBPTHREAD], 1,
			[use libpthread for libcfs library])
	])
	AC_SUBST(ENABLE_LIBPTHREAD, yes)
], [
	AC_SUBST(ENABLE_LIBPTHREAD, no)
	AC_MSG_WARN([Using libpthread for libcfs library is disabled explicitly])
])
AC_SUBST(PTHREAD_LIBS)
]) 
AC_DEFUN([LIBCFS_CONFIG_FILES], [
AC_CONFIG_FILES([
libcfs/Makefile
libcfs/autoMakefile
libcfs/include/Makefile
libcfs/include/libcfs/Makefile
libcfs/include/libcfs/util/Makefile
libcfs/libcfs/Makefile
libcfs/libcfs/autoMakefile
libcfs/libcfs/linux/Makefile
libcfs/libcfs/util/Makefile
libcfs/libcfs/crypto/Makefile
])
]) 
