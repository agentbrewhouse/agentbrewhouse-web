-- AgentBrewHouse: lock down anon (and authenticated) reads of public.agents.
--
-- DO NOT RUN this from the website deploy. Apply it in the Supabase SQL editor
-- (or psql) as a role that owns public.agents, after you have read it.
--
-- Why
-- The marketplace used to call supabase-js with the anon key:
--   sb.from('agents').select('id, avatar_url')
-- That read has moved to GET https://api.agentbrewhouse.io/api/agents/
-- which already returns sanitized public fields, including avatar_url.
-- The anon key is still in the page source (Supabase Auth on the marketplace,
-- the page-view insert, and the admin dashboard). Anyone with that key could
-- previously `select=*` on public.agents, including private columns:
--   system_prompt, endpoint_url, operator_email, contact,
--   agent_api_key_hash, webhook_url, muffin_token
--
-- After this script, anon and authenticated have NO SELECT on public.agents.
-- No column stays readable through the Data API. The website does not need one.
--
-- The backend API must use the service-role key. service_role bypasses RLS
-- and does not need these grants. Do not point the API at the anon key.
-- Nothing in this repository tells the API to use the anon key. The admin
-- page (admin.html) does use the anon key itself, but only for other tables
-- (see the note at the bottom). It does not select from public.agents.
--
-- authenticated is revoked as well. Marketplace sign-in uses Supabase Auth,
-- which does not need SELECT on public.agents. A signed-in browser would
-- otherwise query as `authenticated` and could still read the table.

begin;

-- Table-level privileges. REVOKE ALL also clears table-level SELECT.
revoke all on table public.agents from anon;
revoke all on table public.agents from authenticated;
revoke all on table public.agents from public;

-- Column grants are stored separately. Drop every column SELECT so a
-- leftover GRANT SELECT (system_prompt) cannot survive the table revoke.
do $$
declare
  col text;
begin
  for col in
    select column_name
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'agents'
  loop
    execute format('revoke select (%I) on table public.agents from anon', col);
    execute format('revoke select (%I) on table public.agents from authenticated', col);
    execute format('revoke select (%I) on table public.agents from public', col);
  end loop;
end $$;

-- No GRANT follows. The site does not select any column of public.agents.
--
-- If a future page must read the table directly, grant only the public
-- fields the card already shows, then re-check the policy below.
-- Do not grant the private columns listed at the top.
--
-- grant select (
--   id,
--   agent_id,
--   name,
--   description,
--   category,
--   tags,
--   skills,
--   price_hbar,
--   price_usdc,
--   accepted_currencies,
--   avatar_url,
--   brew_score,
--   status
-- ) on table public.agents to anon;

alter table public.agents enable row level security;

-- Permissive policies are OR'd. A leftover `using (true)` policy would
-- expose every row again the moment any column is granted. Drop SELECT
-- policies that currently let anon or authenticated read the table, then
-- install one policy that only allows rows the café would show.
-- Service role bypasses RLS, so the API keeps working.
do $$
declare
  pol record;
begin
  for pol in
    select policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'agents'
      and cmd in ('SELECT', 'ALL')
      and (
        roles::text ilike '%anon%'
        or roles::text ilike '%authenticated%'
        or roles::text ilike '%public%'
      )
  loop
    execute format('drop policy if exists %I on public.agents', pol.policyname);
  end loop;
end $$;

-- This policy allows no rows until a column GRANT exists, because anon
-- has no SELECT privilege. It is here so a later public-column grant
-- still hides unpaid, private, and non-live rows.
drop policy if exists agents_public_card on public.agents;
create policy agents_public_card
  on public.agents
  for select
  to anon, authenticated
  using (status in ('approved', 'live'));

commit;

-- ---------------------------------------------------------------------------
-- Verification (run after commit, still as the owner)
-- ---------------------------------------------------------------------------
-- Expect zero rows from both privilege queries.

-- select grantee, privilege_type
-- from information_schema.role_table_grants
-- where table_schema = 'public'
--   and table_name = 'agents'
--   and grantee in ('anon', 'authenticated', 'PUBLIC')
-- order by grantee, privilege_type;

-- select grantee, column_name, privilege_type
-- from information_schema.column_privileges
-- where table_schema = 'public'
--   and table_name = 'agents'
--   and grantee in ('anon', 'authenticated', 'PUBLIC')
-- order by grantee, column_name;

-- select policyname, roles, cmd, qual
-- from pg_policies
-- where schemaname = 'public'
--   and tablename = 'agents'
-- order by policyname;

-- With the anon key (the publishable key in marketplace.html), this must
-- fail. Do not expect a row back, even for id or avatar_url.
--
-- curl -sS \
--   -H "apikey: <ANON_KEY>" \
--   -H "Authorization: Bearer <ANON_KEY>" \
--   "https://vzoillfhilpvqxfkozbt.supabase.co/rest/v1/agents?select=*"
--
-- A safe failure is 401 or 403, or an empty error about permission.
-- A JSON array of agent objects means the lockdown did not apply.

-- ---------------------------------------------------------------------------
-- Rollback
-- ---------------------------------------------------------------------------
-- Restores the previous wide-open read. Use it only if something that
-- still depends on anon SELECT breaks. It puts system_prompt and the
-- other private columns back in reach of the anon key.
--
-- begin;
-- grant select on table public.agents to anon, authenticated;
-- drop policy if exists agents_public_card on public.agents;
-- create policy agents_public_read_all
--   on public.agents
--   for select
--   to anon, authenticated
--   using (true);
-- commit;

-- ---------------------------------------------------------------------------
-- Other anon-key uses this script does NOT change
-- ---------------------------------------------------------------------------
-- These are not public.agents. Revoking them here would break the pages
-- that still call them. They are listed so they are not mistaken for a
-- safe public read of the agents table.
--
-- tracker.js
--   POST /rest/v1/page_views
--   writes page, referrer, utm_source, utm_medium, utm_campaign,
--   user_agent, session_id
--
-- admin.html (anon key, not the service-role key)
--   GET page_views?select=page,referrer,utm_source,utm_medium,utm_campaign,session_id,created_at
--   GET beanz_vip?select=email,created_at
--   GET scout_targets?select=name,platform,tagline,status,created_at,url
--
-- index.html Beanz VIP block (commented out, so it does not run)
--   POST /rest/v1/beanz_vip  {email, tier, ip_address}
--   POST /rest/v1/rpc/get_beanz_vip_count
--
-- marketplace.html still uses the anon key for Supabase Auth
-- (signInWithOtp, verifyOtp, getSession, signOut). That is Auth, not a
-- table read. It also loads public avatar images from the
-- agent-avatars storage bucket by URL. Those are objects, not rows.
--
-- Flag: admin.html reads beanz_vip.email and scout_targets with the same
-- anon key that is shipped in the public HTML. That is separate from
-- public.agents, and the API must not be switched over to that key.
