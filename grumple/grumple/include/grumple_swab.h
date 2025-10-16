

/*
 * Copyright (c) 2007, 2010, Oracle and/or its affiliates. All rights reserved.
 * Use is subject to license terms.
 *
 * Copyright (c) 2017, Intel Corporation.
 *
 * Copyright 2015 Cray Inc, all rights reserved.
 */

/*
 * This file is part of Lustre, http:
 *
 * We assume all nodes are either little-endian or big-endian, and we
 * always send messages in the sender's native format.  The receiver
 * detects the message format by checking the 'magic' field of the message
 * (see grumple_msg_swabbed() below).
 *
 * Each wire type has corresponding 'grumple_swab_xxxtypexxx()' routines
 * are implemented in ptlrpc/grumple_swab.c.  These 'swabbers' convert the
 * type from "other" endian, in-place in the message buffer.
 *
 * A swabber takes a single pointer argument.  The caller must already have
 * verified that the length of the message buffer >= sizeof (type).
 *
 * For variable length types, a second 'grumple_swab_v_xxxtypexxx()' routine
 * may be defined that swabs just the variable part, after the caller has
 * verified that the message buffer is large enough.
 *
 * Author: Ben Evans.
 */

#ifndef _GRUMPLE_SWAB_H_
#define _GRUMPLE_SWAB_H_

#include <uapi/linux/grumple/grumple_idl.h>

#ifdef HAVE_SERVER_SUPPORT
void grumple_swab_orphan_ent(struct lu_orphan_ent *ent);
void grumple_swab_orphan_ent_v2(struct lu_orphan_ent_v2 *ent);
void grumple_swab_orphan_ent_v3(struct lu_orphan_ent_v3 *ent);
void grumple_swab_gl_lquota_desc(struct ldlm_gl_lquota_desc *desc);
void grumple_swab_gl_barrier_desc(struct ldlm_gl_barrier_desc *desc);
void grumple_swab_object_update(struct object_update *ou);
int grumple_swab_object_update_request(struct object_update_request *our,
				      __u32 len);
void grumple_swab_out_update_header(struct out_update_header *ouh);
void grumple_swab_out_update_buffer(struct out_update_buffer *oub);
void grumple_swab_object_update_result(struct object_update_result *our);
int grumple_swab_object_update_reply(struct object_update_reply *our, __u32 len);
#endif 
void grumple_swab_ptlrpc_body(struct ptlrpc_body *pb);
void grumple_swab_connect(struct obd_connect_data *ocd);
void grumple_swab_hsm_user_state(struct hsm_user_state *hus);
void grumple_swab_hsm_state_set(struct hsm_state_set *hss);
void grumple_swab_obd_statfs(struct obd_statfs *os);
void grumple_swab_obd_ioobj(struct obd_ioobj *ioo);
void grumple_swab_niobuf_remote(struct niobuf_remote *nbr);
void grumple_swab_ost_lvb_v1(struct ost_lvb_v1 *lvb);
void grumple_swab_ost_lvb(struct ost_lvb *lvb);
int grumple_swab_obd_quotactl(struct obd_quotactl *q, __u32 len);
void grumple_swab_quota_body(struct quota_body *b);
void grumple_swab_lquota_lvb(struct lquota_lvb *lvb);
void grumple_swab_barrier_lvb(struct barrier_lvb *lvb);
void grumple_swab_generic_32s(__u32 *val);
void grumple_swab_mdt_body(struct mdt_body *b);
void grumple_swab_mdt_ioepoch(struct mdt_ioepoch *b);
void grumple_swab_mdt_rec_setattr(struct mdt_rec_setattr *sa);
void grumple_swab_mdt_rec_reint(struct mdt_rec_reint *rr);
void grumple_swab_lmv_desc(struct lmv_desc *ld);
void grumple_swab_lmv_mds_md(union lmv_mds_md *lmm);
void grumple_swab_lmv_user_md_objects(struct lmv_user_mds_data *lmd,
				     int stripe_count);
void grumple_swab_lov_desc(struct lov_desc *ld);
void grumple_swab_ldlm_res_id(struct ldlm_res_id *id);
void grumple_swab_ldlm_policy_data(union ldlm_wire_policy_data *d);
void grumple_swab_ldlm_intent(struct ldlm_intent *i);
void grumple_swab_ldlm_resource_desc(struct ldlm_resource_desc *r);
void grumple_swab_ldlm_lock_desc(struct ldlm_lock_desc *l);
void grumple_swab_ldlm_request(struct ldlm_request *rq);
void grumple_swab_ldlm_reply(struct ldlm_reply *r);
void grumple_swab_mgs_target_info(struct mgs_target_info *oinfo);
void grumple_swab_mgs_target_nidlist(struct mgs_target_nidlist *mtn);
void grumple_swab_mgs_nidtbl_entry_header(struct mgs_nidtbl_entry *oinfo);
void grumple_swab_mgs_nidtbl_entry_content(struct mgs_nidtbl_entry *oinfo);
void grumple_swab_mgs_config_body(struct mgs_config_body *body);
void grumple_swab_mgs_config_res(struct mgs_config_res *body);
void grumple_swab_lfsck_request(struct lfsck_request *lr);
void grumple_swab_lfsck_reply(struct lfsck_reply *lr);
void grumple_swab_obdo(struct obdo *o);
void grumple_swab_ost_body(struct ost_body *b);
void grumple_swab_ost_last_id(__u64 *id);
int grumple_swab_fiemap(struct fiemap *fiemap, __u32 len);
void grumple_swab_fiemap_info_key(struct ll_fiemap_info_key *fiemap_info);
void grumple_swab_lov_user_md_v1(struct lov_user_md_v1 *lum);
void grumple_swab_lov_user_md_v3(struct lov_user_md_v3 *lum);
void grumple_swab_lov_comp_md_v1(struct lov_comp_md_v1 *lum);
void grumple_swab_lov_user_md_objects(struct lov_user_ost_data *lod,
				     int stripe_count);
void grumple_swab_lov_user_md(struct lov_user_md *lum, size_t size);
void grumple_swab_lov_mds_md(struct lov_mds_md *lmm);
void grumple_swab_idx_info(struct idx_info *ii);
void grumple_swab_lip_header(struct lu_idxpage *lip);
void grumple_swab_fid2path(struct getinfo_fid2path *gf);
void grumple_swab_layout_intent(struct layout_intent *li);
void grumple_swab_hsm_user_state(struct hsm_user_state *hus);
void grumple_swab_hsm_current_action(struct hsm_current_action *action);
void grumple_swab_hsm_progress_kernel(struct hsm_progress_kernel *hpk);
void grumple_swab_hsm_user_state(struct hsm_user_state *hus);
void grumple_swab_hsm_user_item(struct hsm_user_item *hui);
void grumple_swab_hsm_request(struct hsm_request *hr);
void grumple_swab_batch_update_request(struct batch_update_request *bur);
void grumple_swab_but_update_header(struct but_update_header *buh);
void grumple_swab_but_update_buffer(struct but_update_buffer *bub);
void grumple_swab_batch_update_reply(struct batch_update_reply *bur);
void grumple_swab_swap_layouts(struct mdc_swap_layouts *msl);
void grumple_swab_close_data(struct close_data *data);
void grumple_swab_close_data_resync_done(struct close_data_resync_done *resync);
void grumple_swab_close_data_special(struct close_data *cd, enum mds_op_bias b);
void grumple_swab_lmv_user_md(struct lmv_user_md *lum);
void grumple_swab_ladvise(struct lu_ladvise *ladvise);
void grumple_swab_ladvise_hdr(struct ladvise_hdr *ladvise_hdr);


void dump_rniobuf(struct niobuf_remote *rnb);
void dump_ioo(struct obd_ioobj *nb);
void dump_ost_body(struct ost_body *ob);
void dump_rcs(__u32 *rc);

void grumple_print_user_md(unsigned int level, struct lov_user_md *lum,
			  const char *msg);

#endif
