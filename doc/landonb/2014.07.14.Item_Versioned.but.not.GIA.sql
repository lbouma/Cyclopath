/*

I found a bug in discussions where a new post version
was saved but the GIA table was not updated (so you
have versions 1 and 2 of the stack_id in item_versioned,
but only the version 1 record in group_item_access (which
then had the wrong valid_until_rid)).

While investigating this, I looked for other item without
group_item_access records -- and there are a lot, but they're
mostly for item that don't use the access control system, such
as node_endpoint. But there are 6063 records for which I cannot
identify the source (the stack_ids don't match any rows in any
of the tables that use stack_ids). There are also 52 geofeatures
without group_item_access records, but these are all marked
deleted, so not really worth our time to fix (and they may be
private watch regions for which we cannot identify the owner).

*/

select count(*) from item_versioned as iv
select iv.* from item_versioned as iv
left outer join group_item_access as gia on (gia.item_id = iv.system_id)
where gia.item_id is null; -- 752562

select count(*) from item_versioned as iv
left outer join group_item_access as gia on (gia.item_id = iv.system_id)
where gia.item_id is null and iv.version = 1 and iv.deleted is false
and iv.valid_start_rid = 1 and iv.valid_until_rid = 2000000000
and (iv.name = '' or iv.name is null)
and iv.branch_id = 2500677; -- 365296 (mostly node_endpoints)
and iv.branch_id = 2538452; -- 367312 (mostly node_endpoints)

select count(iv.*) from item_versioned as iv
left outer join group_item_access as gia on (gia.item_id = iv.system_id)
left outer join node_endpoint as nep on (nep.stack_id = iv.stack_id)
left outer join new_item_policy as nip on (nip.stack_id = iv.stack_id)
left outer join group_ as gp on (gp.stack_id = iv.stack_id)
left outer join group_membership as gm on (gm.stack_id = iv.stack_id)
left outer join work_item as wim on (wim.stack_id = iv.stack_id)
left outer join geofeature as gf on (gf.stack_id = iv.stack_id)
left outer join attachment as atc on (atc.stack_id = iv.stack_id)
left outer join link_value as lv on (lv.stack_id = iv.stack_id)
left outer join route as rte on (rte.stack_id = iv.stack_id)
left outer join post as pst on (pst.stack_id = iv.stack_id)
left outer join thread as thd on (thd.stack_id = iv.stack_id)
left outer join annotation as ann on (ann.stack_id = iv.stack_id)
left outer join attribute as att on (att.stack_id = iv.stack_id)
left outer join branch as br on (br.stack_id = iv.stack_id)
left outer join conflation_job as cjb on (cjb.stack_id = iv.stack_id)
left outer join merge_job as mjb on (mjb.stack_id = iv.stack_id)
left outer join node_traverse as ntr on (ntr.stack_id = iv.stack_id)
left outer join route_analysis_job as raj on (raj.stack_id = iv.stack_id)
left outer join track as trk on (trk.stack_id = iv.stack_id)
left outer join __delete_me_ccpv1_item_watcher as itw on (itw.stack_id = iv.stack_id)
left outer join hausdorff_cache as hce on (hce.stack_id = iv.stack_id)
left outer join tag as tag on (tag.stack_id = iv.stack_id)
left outer join tiles_cache_byway_segment as tcb on (tcb.stack_id = iv.stack_id)

where gia.item_id is null
  and nep.stack_id is null -- 26376
  and nip.stack_id is null -- 26335
  and gp.stack_id is null -- 19584
  and gm.stack_id is null -- 6116
  and wim.stack_id is null -- 6116
  and gf.stack_id is null -- 6064 !!!!! <-- 52 Gfs w/o GIA records (deleted)
  and atc.stack_id is null -- 6064
  and lv.stack_id is null -- 6063 !!!!! <--  1 Lval w/o GIA record (my post)
  and rte.stack_id is null -- 6063
  and pst.stack_id is null -- 6063
  and thd.stack_id is null -- 6063
  and ann.stack_id is null -- 6063
  and att.stack_id is null -- 6063
  and br.stack_id is null -- 6063
  and cjb.stack_id is null -- 6063
  and mjb.stack_id is null -- 6063
  and ntr.stack_id is null -- 6063
  and raj.stack_id is null -- 6063
  and trk.stack_id is null -- 6063
  and itw.stack_id is null -- 6063
  and hce.stack_id is null -- 6063
  and tag.stack_id is null -- 6063
  and tcb.stack_id is null -- 6063

  ;
-- What are the remaining 6063 records??

