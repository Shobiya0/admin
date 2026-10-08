-- CHOICE DIGITAL MARKETING - SUPABASE SETUP
-- Run this in Supabase SQL Editor before production use.
create extension if not exists pgcrypto;

create table if not exists public.clients(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz default now()
);

create table if not exists public.profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  client_id uuid references public.clients(id) on delete cascade,
  role text not null check(role in ('super_admin','client_editor')) default 'client_editor',
  email text,
  created_at timestamptz default now()
);

create table if not exists public.site_content(
  id uuid primary key default gen_random_uuid(),
  client_id uuid unique not null references public.clients(id) on delete cascade,
  content jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id),
  updated_at timestamptz default now()
);

create table if not exists public.pricing(
  id text primary key,
  title text not null,
  price text not null,
  unit text not null,
  items jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  updated_at timestamptz default now()
);

create table if not exists public.notifications(
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  message text not null,
  created_at timestamptz default now(),
  read boolean default false
);

create table if not exists public.activity_logs(
  id uuid primary key default gen_random_uuid(),
  client_id uuid references public.clients(id) on delete cascade,
  user_id uuid references auth.users(id),
  action text not null,
  details jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

alter table public.clients enable row level security;
alter table public.profiles enable row level security;
alter table public.site_content enable row level security;
alter table public.pricing enable row level security;
alter table public.notifications enable row level security;
alter table public.activity_logs enable row level security;

create or replace function public.is_super_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from profiles where id=auth.uid() and role='super_admin')
$$;
create or replace function public.my_client_id() returns uuid language sql stable security definer set search_path=public as $$
  select client_id from profiles where id=auth.uid()
$$;

-- Public website can read pricing. Only admin can change it.
drop policy if exists pricing_public_read on public.pricing;
create policy pricing_public_read on public.pricing for select using (true);
drop policy if exists pricing_admin_write on public.pricing;
create policy pricing_admin_write on public.pricing for all using(public.is_super_admin()) with check(public.is_super_admin());

drop policy if exists profiles_self on public.profiles;
create policy profiles_self on public.profiles for select using(id=auth.uid() or public.is_super_admin());
drop policy if exists clients_access on public.clients;
create policy clients_access on public.clients for select using(public.is_super_admin() or id=public.my_client_id());
drop policy if exists site_read on public.site_content;
create policy site_read on public.site_content for select using(public.is_super_admin() or client_id=public.my_client_id());
drop policy if exists site_update on public.site_content;
create policy site_update on public.site_content for update using(public.is_super_admin() or client_id=public.my_client_id()) with check(public.is_super_admin() or client_id=public.my_client_id());
drop policy if exists site_insert on public.site_content;
create policy site_insert on public.site_content for insert with check(public.is_super_admin());
drop policy if exists notifications_admin on public.notifications;
create policy notifications_admin on public.notifications for select using(public.is_super_admin());
drop policy if exists activity_admin on public.activity_logs;
create policy activity_admin on public.activity_logs for select using(public.is_super_admin() or client_id=public.my_client_id());

create or replace function public.enforce_client_editable_fields() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is not null and not public.is_super_admin() then
    new.content := jsonb_build_object(
      'hero_title', coalesce(new.content->'hero_title', old.content->'hero_title'),
      'hero_description', coalesce(new.content->'hero_description', old.content->'hero_description'),
      'phone', coalesce(new.content->'phone', old.content->'phone'),
      'whatsapp', coalesce(new.content->'whatsapp', old.content->'whatsapp'),
      'email', coalesce(new.content->'email', old.content->'email'),
      'address', coalesce(new.content->'address', old.content->'address'),
      'about_text', coalesce(new.content->'about_text', old.content->'about_text')
    );
  end if;
  return new;
end;
$$;
drop trigger if exists trg_enforce_client_fields on public.site_content;
create trigger trg_enforce_client_fields before update on public.site_content for each row execute function public.enforce_client_editable_fields();

create or replace function public.log_site_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is not null and not public.is_super_admin() then
    insert into activity_logs(client_id,user_id,action,details) values(new.client_id,auth.uid(),'site_content_updated',jsonb_build_object('before',old.content,'after',new.content));
    insert into notifications(client_id,message) values(new.client_id,'Client updated website content.');
  end if;
  new.updated_at=now();
  return new;
end;
$$;
drop trigger if exists trg_site_change on public.site_content;
create trigger trg_site_change after update on public.site_content for each row execute function public.log_site_change();

insert into public.pricing(id,title,price,unit,items,sort_order) values
('gbp-setup','Google Business Profile — Setup','₹4,999','One time','["Google Maps setup","WhatsApp button","Call button","1 low-density keyword targeted for first-page ranking"]',1),
('gbp-maintenance','Google Business Profile — Maintenance','₹1,999','/ month','["Ongoing profile optimization","Up to 10 high-density keywords targeted","Regular performance review"]',2),
('static-site','Basic Static Landing Page','₹4,999+','Starting','["Domain + hosting","Website content","Responsive landing page","Additional features priced separately"]',3),
('multi-site','Multi-Page Website','₹6,999+','Starting','["Multiple pages","Separate admin panel","Responsive design","Animation/custom features priced based on scope"]',4),
('ai-poster','AI Poster + Content','₹199+','Per creative','["AI-assisted design","Marketing content","Fast turnaround"]',5),
('ai-video','AI Video','₹499+','30 seconds','["AI video creative","Short-form social format"]',6),
('voiceover','Professional Voiceover','₹400','Up to 60 sec','["Professional voiceover","Same-day delivery available"]',7),
('meta-ads','Meta Ads Campaign','₹2,999+','/ week','["Campaign setup & management","Scope based on business requirements","Pricing may vary by campaign needs"]',8)
on conflict (id) do nothing;


-- Enable realtime for admin pricing changes so open public pages update without a manual refresh.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='pricing'
  ) then
    alter publication supabase_realtime add table public.pricing;
  end if;
exception when undefined_object then
  null;
end $$;

-- BOOTSTRAP THE MAIN ADMIN AFTER CREATING rshofiya@gmail.com IN SUPABASE AUTH:
-- 1) Create the user in Authentication > Users.
-- 2) Copy the user's UUID.
-- 3) Run:
-- insert into public.profiles(id,role,email) values('PASTE_AUTH_USER_UUID_HERE','super_admin','rshofiya@gmail.com')
-- on conflict (id) do update set role='super_admin', email='rshofiya@gmail.com';
