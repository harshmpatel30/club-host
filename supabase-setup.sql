-- ════════════════════════════════════════════════════════════════════
--  Club Host · one-time Supabase setup
--  Paste this whole file into Supabase → SQL Editor → New query → Run.
--  It is safe to run again (it updates the functions and keeps the data).
--
--  What it creates
--    • `clubs`: each club's records, ENCRYPTED with the club password
--      (the server never sees names, marks or sessions);
--    • `club_attempts`: recent wrong-password attempts, used to slow
--      down anyone trying to guess a club's password;
--    • five functions the website calls. Nobody can read or change the
--      tables directly: every read or save must prove it knows the club
--      password (a key derived from it on the device, never the password).
-- ════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.clubs (
  key         text primary key,
  name        text not null,
  salt        text not null,
  iter        integer not null,
  token_hash  text not null,
  blob        text not null,
  version     bigint not null default 1,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.clubs add column if not exists made_by text;

-- limits (re-applied on every run, so older setups get the current ones)
alter table public.clubs drop constraint if exists clubs_key_check;
alter table public.clubs drop constraint if exists clubs_name_check;
alter table public.clubs drop constraint if exists clubs_salt_check;
alter table public.clubs drop constraint if exists clubs_iter_check;
alter table public.clubs drop constraint if exists clubs_blob_check;
alter table public.clubs add constraint clubs_key_check  check (char_length(key) between 1 and 100);
alter table public.clubs add constraint clubs_name_check check (char_length(name) between 1 and 100);
alter table public.clubs add constraint clubs_salt_check check (char_length(salt) between 8 and 64);
alter table public.clubs add constraint clubs_iter_check check (iter between 100000 and 5000000);
alter table public.clubs add constraint clubs_blob_check check (octet_length(blob) <= 1000000);
create index if not exists clubs_created_at on public.clubs (created_at);

create table if not exists public.club_attempts (
  key  text not null,
  who  text not null,
  at   timestamptz not null default now()
);
create index if not exists club_attempts_key_who_at on public.club_attempts (key, who, at);
create index if not exists club_attempts_at on public.club_attempts (at);

-- lock both tables: no policies means no direct access for the public API keys
alter table public.clubs enable row level security;
alter table public.club_attempts enable row level security;
revoke all on table public.clubs from anon, authenticated;
revoke all on table public.club_attempts from anon, authenticated;

-- ── helpers (not callable from the website) ─────────────────────────

-- who is calling: the visitor's IP address as passed on by Supabase's gateway
create or replace function public.club_caller()
returns text
language sql stable
set search_path = public, extensions
as $$
  select coalesce(
    nullif(current_setting('request.headers', true)::json->>'cf-connecting-ip', ''),
    nullif(trim(split_part(current_setting('request.headers', true)::json->>'x-forwarded-for', ',', 1)), ''),
    'unknown');
$$;

-- refuse after 10 wrong passwords for one club from one address within 15 minutes
create or replace function public.club_guard(p_key text)
returns void
language plpgsql
set search_path = public, extensions
as $$
begin
  delete from public.club_attempts where at < now() - interval '1 day';
  if (select count(*) from public.club_attempts a
       where a.key = p_key and a.who = public.club_caller()
         and a.at > now() - interval '15 minutes') >= 10 then
    raise exception 'slow' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.club_fail(p_key text)
returns void
language sql
set search_path = public, extensions
as $$
  insert into public.club_attempts (key, who) values (p_key, public.club_caller());
$$;

create or replace function public.club_token_ok(p_key text, p_token text)
returns boolean
language sql stable
set search_path = public, extensions
as $$
  select exists (select 1 from public.clubs c
                  where c.key = p_key and c.token_hash = encode(digest(p_token, 'sha256'), 'hex'));
$$;

-- ── the five functions the website calls ────────────────────────────

-- 1 · what a device needs before it can derive the club key (never secret)
create or replace function public.club_salt(p_key text)
returns table (name text, salt text, iter integer)
language sql stable security definer
set search_path = public, extensions
as $$
  select c.name, c.salt, c.iter from public.clubs c where c.key = p_key;
$$;

-- 2 · start a club (at most 5 per address and 30 in total per hour)
create or replace function public.club_create(
  p_key text, p_name text, p_salt text, p_iter integer, p_token text, p_blob text)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare me text := public.club_caller();
begin
  if octet_length(p_blob) > 1000000 then
    raise exception 'too_big' using errcode = 'P0001';
  end if;
  if char_length(coalesce(p_key, '')) not between 1 and 100 or char_length(coalesce(p_name, '')) not between 1 and 100 then
    raise exception 'bad_name' using errcode = 'P0001';
  end if;
  if (select count(*) from public.clubs c where c.created_at > now() - interval '1 hour') >= 30
     or (select count(*) from public.clubs c where c.made_by = me and c.created_at > now() - interval '1 hour') >= 5 then
    raise exception 'busy' using errcode = 'P0001';
  end if;
  insert into public.clubs (key, name, salt, iter, token_hash, blob, made_by)
  values (p_key, p_name, p_salt, p_iter, encode(digest(p_token, 'sha256'), 'hex'), p_blob, me);
  return 1;
exception
  when unique_violation then raise exception 'taken' using errcode = 'P0001';
  when check_violation then raise exception 'bad_name' using errcode = 'P0001';
end;
$$;

-- 3 · open a club. A wrong password returns no row (instead of an error) so the attempt is counted.
create or replace function public.club_open(p_key text, p_token text)
returns table (name text, blob text, version bigint, created_at timestamptz)
language plpgsql security definer
set search_path = public, extensions
as $$
begin
  if not exists (select 1 from public.clubs c where c.key = p_key) then
    raise exception 'missing' using errcode = 'P0001';
  end if;
  perform public.club_guard(p_key);
  if not public.club_token_ok(p_key, p_token) then
    perform public.club_fail(p_key);
    return;
  end if;
  return query
    select c.name, c.blob, c.version, c.created_at from public.clubs c where c.key = p_key;
end;
$$;

-- 4 · the cheap "has anything changed?" check devices make every few seconds (-1 = wrong password)
create or replace function public.club_version(p_key text, p_token text)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare v bigint;
begin
  if not exists (select 1 from public.clubs c where c.key = p_key) then
    raise exception 'missing' using errcode = 'P0001';
  end if;
  perform public.club_guard(p_key);
  if not public.club_token_ok(p_key, p_token) then
    perform public.club_fail(p_key);
    return -1;
  end if;
  select c.version into v from public.clubs c where c.key = p_key;
  return v;
end;
$$;

-- 5 · save: only succeeds on top of the version the device last saw, so two founders saving
--     at once can never overwrite each other (the second is told 'conflict', merges, saves again)
create or replace function public.club_save(p_key text, p_token text, p_blob text, p_base bigint)
returns bigint
language plpgsql security definer
set search_path = public, extensions
as $$
declare v bigint;
begin
  if octet_length(p_blob) > 1000000 then
    raise exception 'too_big' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.clubs c where c.key = p_key) then
    raise exception 'missing' using errcode = 'P0001';
  end if;
  perform public.club_guard(p_key);
  if not public.club_token_ok(p_key, p_token) then
    perform public.club_fail(p_key);
    return -1;
  end if;
  update public.clubs c
     set blob = p_blob, version = c.version + 1, updated_at = now()
   where c.key = p_key and c.version = p_base
  returning c.version into v;
  if v is null then
    raise exception 'conflict' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

-- only the five functions are reachable from the website; the helpers are not
revoke all on function public.club_caller() from public, anon, authenticated;
revoke all on function public.club_guard(text) from public, anon, authenticated;
revoke all on function public.club_fail(text) from public, anon, authenticated;
revoke all on function public.club_token_ok(text, text) from public, anon, authenticated;
revoke all on function public.club_salt(text) from public;
revoke all on function public.club_create(text, text, text, integer, text, text) from public;
revoke all on function public.club_open(text, text) from public;
revoke all on function public.club_version(text, text) from public;
revoke all on function public.club_save(text, text, text, bigint) from public;
grant execute on function public.club_salt(text) to anon, authenticated;
grant execute on function public.club_create(text, text, text, integer, text, text) to anon, authenticated;
grant execute on function public.club_open(text, text) to anon, authenticated;
grant execute on function public.club_version(text, text) to anon, authenticated;
grant execute on function public.club_save(text, text, text, bigint) to anon, authenticated;

-- make the website's API notice the changes straight away
notify pgrst, 'reload schema';
