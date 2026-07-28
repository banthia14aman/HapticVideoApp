-- HapticVideoApp — Supabase schema
-- Run in the SQL editor of your Supabase project (or `supabase db push`).
-- NOTE: for the app's current sign-up flow to work, disable
-- "Confirm email" in Auth → Providers → Email (prototype setting) —
-- otherwise signUp returns no session and the profile insert is blocked by RLS.

-- ── Tables ────────────────────────────────────────────────────────────────

create table if not exists public.users (
  id              uuid primary key references auth.users (id) on delete cascade,
  username        text not null unique,
  display_name    text not null,
  email           text not null,
  videos_uploaded int  not null default 0,
  created_at      timestamptz not null default now()
);

create table if not exists public.videos (
  id                uuid primary key,
  title             text not null,
  description       text,
  video_url         text not null,
  thumbnail_url     text not null,
  uploader_id       uuid not null references public.users (id) on delete cascade,
  uploader_username text not null,
  uploaded_at       timestamptz not null default now(),
  duration          double precision not null,
  has_haptics       boolean not null default false,
  haptics_url       text,
  views             int not null default 0
);

create index if not exists videos_uploaded_at_idx on public.videos (uploaded_at desc);

-- ── Row Level Security ────────────────────────────────────────────────────

alter table public.users  enable row level security;
alter table public.videos enable row level security;

create policy "users are publicly readable"
  on public.users for select using (true);
create policy "users can insert their own profile"
  on public.users for insert with check (auth.uid() = id);
create policy "users can update their own profile"
  on public.users for update using (auth.uid() = id);

create policy "videos are publicly readable"
  on public.videos for select using (true);
create policy "owners can insert videos"
  on public.videos for insert with check (auth.uid() = uploader_id);
create policy "owners can delete videos"
  on public.videos for delete using (auth.uid() = uploader_id);

-- ── View counter RPC (atomic; called by CloudDataStore.incrementViews) ───

create or replace function public.increment_views(p_video_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.videos set views = views + 1 where id = p_video_id;
$$;

-- ── Storage buckets (public read; app uses getPublicURL) ─────────────────

insert into storage.buckets (id, name, public) values
  ('videos', 'videos', true),
  ('thumbnails', 'thumbnails', true),
  ('haptics', 'haptics', true)
on conflict (id) do nothing;

create policy "public read app buckets"
  on storage.objects for select
  using (bucket_id in ('videos', 'thumbnails', 'haptics'));

create policy "authenticated upload to app buckets"
  on storage.objects for insert to authenticated
  with check (bucket_id in ('videos', 'thumbnails', 'haptics'));

create policy "authenticated update app buckets"
  on storage.objects for update to authenticated
  using (bucket_id in ('videos', 'thumbnails', 'haptics'));

create policy "authenticated delete from app buckets"
  on storage.objects for delete to authenticated
  using (bucket_id in ('videos', 'thumbnails', 'haptics'));
