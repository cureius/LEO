-- Rules now support AND-within-group / OR-across-groups condition pairing
-- (disjunctive normal form: a rule matches if ANY group matches, and a
-- group matches only if ALL its conditions match) instead of a single flat
-- AND-only list. Renaming the column alongside the shape change so a
-- reader of the schema doesn't find "conditions" holding groups-of-
-- conditions instead of conditions.
alter table public.automation_rules rename column conditions to condition_groups;

-- Wrap every existing rule's flat condition list in a single group so
-- existing rules keep matching exactly as before (one AND'd group is
-- equivalent to the old all-conditions-must-match semantics). Guarded so
-- this is safe to re-run: skips anything already shaped as groups (each
-- element already has a "conditions" key) or empty.
update public.automation_rules
set condition_groups = jsonb_build_array(jsonb_build_object('id', gen_random_uuid()::text, 'conditions', condition_groups))
where jsonb_typeof(condition_groups) = 'array'
  and condition_groups != '[]'::jsonb
  and not (condition_groups -> 0 ? 'conditions');
