-- OUR MOMENTS: Supabase schema for a private two-person room.
-- Run this whole script once in Supabase Dashboard -> SQL Editor.
-- Use only the project's publishable/anon key in the app. NEVER use service_role / secret keys here.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.couple_rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Our Moments',
  invite_code_hash text not null unique,
  anniversary_date date,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.couple_members (
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null default 'ふたり',
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

create or replace function public.is_room_member(check_room_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.couple_members cm
    where cm.room_id = check_room_id and cm.user_id = auth.uid()
  );
$$;

create or replace function public.create_couple_room(
  p_room_name text,
  p_invite_code text,
  p_display_name text,
  p_anniversary_date date default null
)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  new_room_id uuid;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if length(trim(coalesce(p_invite_code, ''))) < 12 then raise exception 'Invite code is too short.'; end if;
  insert into public.couple_rooms(name, invite_code_hash, anniversary_date, created_by)
  values (
    coalesce(nullif(trim(p_room_name), ''), 'Our Moments'),
    encode(extensions.digest(upper(trim(p_invite_code)), 'sha256'), 'hex'),
    p_anniversary_date,
    auth.uid()
  ) returning id into new_room_id;
  insert into public.couple_members(room_id, user_id, display_name)
  values (new_room_id, auth.uid(), coalesce(nullif(trim(p_display_name), ''), 'あなた'));
  return new_room_id;
end;
$$;

create or replace function public.join_couple_room(p_invite_code text, p_display_name text)
returns uuid
language plpgsql security definer
set search_path = ''
as $$
declare
  target_room_id uuid;
  member_count integer;
begin
  if auth.uid() is null then raise exception 'Please sign in first.'; end if;
  if length(trim(coalesce(p_invite_code, ''))) < 12 then raise exception 'Invite code is invalid.'; end if;
  select r.id into target_room_id
  from public.couple_rooms r
  where r.invite_code_hash = encode(extensions.digest(upper(trim(p_invite_code)), 'sha256'), 'hex')
  limit 1;
  if target_room_id is null then raise exception 'Invite code not found.'; end if;
  perform 1 from public.couple_rooms r where r.id = target_room_id for update;
  select count(*) into member_count from public.couple_members cm where cm.room_id = target_room_id;
  if not exists (select 1 from public.couple_members cm where cm.room_id = target_room_id and cm.user_id = auth.uid()) and member_count >= 2 then
    raise exception 'This room already has two members.';
  end if;
  insert into public.couple_members(room_id, user_id, display_name)
  values (target_room_id, auth.uid(), coalesce(nullif(trim(p_display_name), ''), '恋人'))
  on conflict (room_id, user_id) do update set display_name = excluded.display_name;
  return target_room_id;
end;
$$;

revoke all on function public.is_room_member(uuid) from public, anon;
grant execute on function public.is_room_member(uuid) to authenticated;
revoke all on function public.create_couple_room(text, text, text, date) from public, anon;
grant execute on function public.create_couple_room(text, text, text, date) to authenticated;
revoke all on function public.join_couple_room(text, text) from public, anon;
grant execute on function public.join_couple_room(text, text) to authenticated;

create table if not exists public.memories (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  title text not null,
  place text not null default '',
  body text not null default '',
  photo_path text,
  created_at timestamptz not null default now()
);

create table if not exists public.letters (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid references auth.users(id) on delete set null,
  sender_label text not null default 'ふたり',
  title text not null,
  body text not null,
  unlock_date date,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  sender_label text not null default 'ふたり',
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.plans (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  title text not null,
  details text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.meal_choices (
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  choice_date date not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  genre text not null,
  moods text[] not null default '{}',
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (room_id, choice_date, user_id)
);

create table if not exists public.mood_entries (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  moods text[] not null default '{}',
  note text not null default '',
  shared boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.relationship_requests (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('want','improve')),
  body text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.surprises (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.couple_rooms(id) on delete cascade,
  creator_id uuid not null references auth.users(id) on delete cascade,
  target_user_id uuid references auth.users(id) on delete set null,
  title text not null,
  unlock_date date not null,
  teaser text not null,
  theme text not null default '✨ 星空',
  created_at timestamptz not null default now()
);

create table if not exists public.surprise_secrets (
  surprise_id uuid primary key references public.surprises(id) on delete cascade,
  secret_message text not null,
  code_hint text not null default '',
  created_at timestamptz not null default now()
);

-- Enable row-level security on every application table.
alter table public.couple_rooms enable row level security;
alter table public.couple_members enable row level security;
alter table public.memories enable row level security;
alter table public.letters enable row level security;
alter table public.messages enable row level security;
alter table public.plans enable row level security;
alter table public.meal_choices enable row level security;
alter table public.mood_entries enable row level security;
alter table public.relationship_requests enable row level security;
alter table public.surprises enable row level security;
alter table public.surprise_secrets enable row level security;

-- Idempotent policies: drop and recreate on re-running the script.
drop policy if exists "room members can view their room" on public.couple_rooms;
create policy "room members can view their room" on public.couple_rooms for select to authenticated using (public.is_room_member(id));
drop policy if exists "room members can update their room" on public.couple_rooms;
create policy "room members can update their room" on public.couple_rooms for update to authenticated using (public.is_room_member(id)) with check (public.is_room_member(id));
drop policy if exists "room members can view members" on public.couple_members;
create policy "room members can view members" on public.couple_members for select to authenticated using (public.is_room_member(room_id));

-- Couple-shared tables: members can read the room; new rows must identify the signed-in author.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['memories','letters','messages','plans','relationship_requests'] LOOP
    EXECUTE format('drop policy if exists %I on public.%I', 'room members can access '||t, t);
    EXECUTE format('drop policy if exists %I on public.%I', 'members can read '||t, t);
    EXECUTE format('drop policy if exists %I on public.%I', 'members can insert own '||t, t);
    EXECUTE format('drop policy if exists %I on public.%I', 'members can update '||t, t);
    EXECUTE format('drop policy if exists %I on public.%I', 'members can delete '||t, t);
    EXECUTE format('create policy %I on public.%I for select to authenticated using (public.is_room_member(room_id))', 'members can read '||t, t);
    EXECUTE format('create policy %I on public.%I for insert to authenticated with check (public.is_room_member(room_id) and author_id = auth.uid())', 'members can insert own '||t, t);
    IF t = 'letters' THEN
      EXECUTE format('create policy %I on public.%I for update to authenticated using (public.is_room_member(room_id) and (author_id = auth.uid() or recipient_id = auth.uid())) with check (public.is_room_member(room_id) and (author_id = auth.uid() or recipient_id = auth.uid()))', 'members can update '||t, t);
    ELSIF t = 'messages' THEN
      -- Read receipts are written by the recipient, so room members may update message rows.
      EXECUTE format('create policy %I on public.%I for update to authenticated using (public.is_room_member(room_id)) with check (public.is_room_member(room_id))', 'members can update '||t, t);
    ELSE
      EXECUTE format('create policy %I on public.%I for update to authenticated using (public.is_room_member(room_id) and author_id = auth.uid()) with check (public.is_room_member(room_id) and author_id = auth.uid())', 'members can update '||t, t);
    END IF;
    EXECUTE format('create policy %I on public.%I for delete to authenticated using (public.is_room_member(room_id) and author_id = auth.uid())', 'members can delete '||t, t);
  END LOOP;
END $$;

-- Future-dated letters remain invisible to the recipient until their opening date.
drop policy if exists "members can read letters" on public.letters;
create policy "members can read letters" on public.letters for select to authenticated using (
  public.is_room_member(room_id) and (author_id = auth.uid() or unlock_date is null or unlock_date <= current_date)
);

-- Both members can read meal choices, but each member can only write their own choice.
drop policy if exists "room members can access meal_choices" on public.meal_choices;
drop policy if exists "members can read meal choices" on public.meal_choices;
create policy "members can read meal choices" on public.meal_choices for select to authenticated using (public.is_room_member(room_id));
drop policy if exists "members manage their own meal choice" on public.meal_choices;
create policy "members manage their own meal choice" on public.meal_choices for insert to authenticated with check (public.is_room_member(room_id) and user_id = auth.uid());
drop policy if exists "members update their own meal choice" on public.meal_choices;
create policy "members update their own meal choice" on public.meal_choices for update to authenticated using (public.is_room_member(room_id) and user_id = auth.uid()) with check (public.is_room_member(room_id) and user_id = auth.uid());

-- Personal mood notes are private unless the author enables sharing.
drop policy if exists "room members can access mood_entries" on public.mood_entries;
drop policy if exists "members read shared moods or their own" on public.mood_entries;
create policy "members read shared moods or their own" on public.mood_entries for select to authenticated using (public.is_room_member(room_id) and (shared = true or author_id = auth.uid()));
drop policy if exists "members write their own moods" on public.mood_entries;
create policy "members write their own moods" on public.mood_entries for insert to authenticated with check (public.is_room_member(room_id) and author_id = auth.uid());
drop policy if exists "members update their own moods" on public.mood_entries;
create policy "members update their own moods" on public.mood_entries for update to authenticated using (public.is_room_member(room_id) and author_id = auth.uid()) with check (public.is_room_member(room_id) and author_id = auth.uid());
drop policy if exists "members delete their own moods" on public.mood_entries;
create policy "members delete their own moods" on public.mood_entries for delete to authenticated using (public.is_room_member(room_id) and author_id = auth.uid());

-- Surprise teaser is visible to both members. The secret body is visible to its creator immediately,
-- and to the recipient only on/after the unlock date.
drop policy if exists "room members can access surprises" on public.surprises;
drop policy if exists "members can read surprises" on public.surprises;
create policy "members can read surprises" on public.surprises for select to authenticated using (public.is_room_member(room_id));
drop policy if exists "creator can insert surprises" on public.surprises;
create policy "creator can insert surprises" on public.surprises for insert to authenticated with check (public.is_room_member(room_id) and creator_id = auth.uid());
drop policy if exists "creator can update surprises" on public.surprises;
create policy "creator can update surprises" on public.surprises for update to authenticated using (public.is_room_member(room_id) and creator_id = auth.uid()) with check (public.is_room_member(room_id) and creator_id = auth.uid());
drop policy if exists "creator can delete surprises" on public.surprises;
create policy "creator can delete surprises" on public.surprises for delete to authenticated using (public.is_room_member(room_id) and creator_id = auth.uid());
drop policy if exists "creators and released recipients can read secrets" on public.surprise_secrets;
create policy "creators and released recipients can read secrets" on public.surprise_secrets for select to authenticated using (
  exists (select 1 from public.surprises s where s.id = surprise_id and public.is_room_member(s.room_id)
    and (s.creator_id = auth.uid() or (s.target_user_id = auth.uid() and s.unlock_date <= current_date)))
);
drop policy if exists "surprise creator can write secret" on public.surprise_secrets;
create policy "surprise creator can write secret" on public.surprise_secrets for insert to authenticated with check (
  exists (select 1 from public.surprises s where s.id = surprise_id and s.creator_id = auth.uid() and public.is_room_member(s.room_id))
);
drop policy if exists "surprise creator can update secret" on public.surprise_secrets;
create policy "surprise creator can update secret" on public.surprise_secrets for update to authenticated using (
  exists (select 1 from public.surprises s where s.id = surprise_id and s.creator_id = auth.uid() and public.is_room_member(s.room_id))
) with check (
  exists (select 1 from public.surprises s where s.id = surprise_id and s.creator_id = auth.uid() and public.is_room_member(s.room_id))
);

-- Private photo storage: objects are stored under <room-uuid>/<user-uuid>/<filename>.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('couple-photos', 'couple-photos', false, 1048576, array['image/jpeg','image/webp','image/png'])
on conflict (id) do update set public = false, file_size_limit = 1048576, allowed_mime_types = array['image/jpeg','image/webp','image/png'];

drop policy if exists "room members can read couple photos" on storage.objects;
create policy "room members can read couple photos" on storage.objects for select to authenticated using (
  bucket_id = 'couple-photos' and public.is_room_member(((storage.foldername(name))[1])::uuid)
);
drop policy if exists "room members can upload couple photos" on storage.objects;
create policy "room members can upload couple photos" on storage.objects for insert to authenticated with check (
  bucket_id = 'couple-photos' and public.is_room_member(((storage.foldername(name))[1])::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
);
drop policy if exists "room members can update their uploaded photos" on storage.objects;
create policy "room members can update their uploaded photos" on storage.objects for update to authenticated using (
  bucket_id = 'couple-photos' and public.is_room_member(((storage.foldername(name))[1])::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
) with check (
  bucket_id = 'couple-photos' and public.is_room_member(((storage.foldername(name))[1])::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
);
drop policy if exists "room members can delete their uploaded photos" on storage.objects;
create policy "room members can delete their uploaded photos" on storage.objects for delete to authenticated using (
  bucket_id = 'couple-photos' and public.is_room_member(((storage.foldername(name))[1])::uuid)
  and (storage.foldername(name))[2] = auth.uid()::text
);

-- Authorize private Realtime channels for typing/presence. Channel topic format: our-moments:<room-uuid>.
alter table realtime.messages enable row level security;
drop policy if exists "room members can receive private channel events" on realtime.messages;
create policy "room members can receive private channel events" on realtime.messages for select to authenticated using (
  realtime.topic() like 'our-moments:%' and public.is_room_member((split_part(realtime.topic(), ':', 2))::uuid)
);
drop policy if exists "room members can send private channel events" on realtime.messages;
create policy "room members can send private channel events" on realtime.messages for insert to authenticated with check (
  realtime.topic() like 'our-moments:%' and public.is_room_member((split_part(realtime.topic(), ':', 2))::uuid)
);

-- Enable live database events for the screens that need cross-device updates.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['messages','letters','memories','plans','meal_choices','mood_entries','relationship_requests','surprises'] LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t
    ) THEN
      EXECUTE format('alter publication supabase_realtime add table public.%I', t);
    END IF;
  END LOOP;
END $$;
