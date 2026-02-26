-- AI2AI locked DB layer (PostgreSQL)
-- Pattern: runtime sends only opId + typed args. SQL text is not accepted from runtime.

create schema if not exists ai2ai;

create table if not exists ai2ai.kv_state (
  state_key text primary key,
  state_value text not null,
  rev bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists ai2ai.session_store (
  session_key text primary key,
  user_id bigint not null,
  expires_at bigint not null,
  updated_at timestamptz not null default now()
);

create table if not exists ai2ai.audit_log (
  id bigserial primary key,
  actor text not null,
  action text not null,
  target text not null,
  ts bigint not null
);

create or replace function ai2ai.op_9001()
returns table(ok int)
language sql
as $$
  select 1::int;
$$;

create or replace function ai2ai.op_1001(p_session_key text)
returns table(session_key text, user_id bigint, expires_at bigint)
language sql
as $$
  select s.session_key, s.user_id, s.expires_at
  from ai2ai.session_store s
  where s.session_key = p_session_key;
$$;

create or replace function ai2ai.op_1002(p_session_key text, p_user_id bigint, p_expires_at bigint)
returns table(updated int)
language sql
as $$
  insert into ai2ai.session_store(session_key, user_id, expires_at)
  values (p_session_key, p_user_id, p_expires_at)
  on conflict (session_key) do update set
    user_id = excluded.user_id,
    expires_at = excluded.expires_at,
    updated_at = now();
  select 1::int;
$$;

create or replace function ai2ai.op_2001(p_state_key text)
returns table(state_key text, state_value text, rev bigint)
language sql
as $$
  select k.state_key, k.state_value, k.rev
  from ai2ai.kv_state k
  where k.state_key = p_state_key;
$$;

create or replace function ai2ai.op_2002(p_state_key text, p_state_value text, p_rev bigint)
returns table(updated int)
language sql
as $$
  insert into ai2ai.kv_state(state_key, state_value, rev)
  values (p_state_key, p_state_value, p_rev)
  on conflict (state_key) do update set
    state_value = excluded.state_value,
    rev = excluded.rev,
    updated_at = now();
  select 1::int;
$$;

create or replace function ai2ai.op_3001(p_actor text, p_action text, p_target text, p_ts bigint)
returns table(inserted int)
language sql
as $$
  insert into ai2ai.audit_log(actor, action, target, ts)
  values (p_actor, p_action, p_target, p_ts);
  select 1::int;
$$;

create or replace function ai2ai.op_4001(p_state_key text)
returns table(deleted int)
language sql
as $$
  delete from ai2ai.kv_state where state_key = p_state_key;
  select 1::int;
$$;
