-- Run this in the Supabase SQL editor to set up the sync target.
-- Enable PostGIS first: Database > Extensions > postgis (or the line below).
create extension if not exists postgis;

create table if not exists submissions (
  id uuid primary key,                 -- client-generated UUID, so offline inserts never collide
  form_id text not null,
  form_version integer not null,
  data jsonb not null,                 -- the full schema-driven answer set
  lat double precision,
  lng double precision,
  geom geometry(Point, 4326)
    generated always as (
      case when lat is not null and lng is not null
        then st_setsrid(st_makepoint(lng, lat), 4326)
        else null
      end
    ) stored,
  created_at timestamptz not null,
  received_at timestamptz not null default now(),
  device_id text not null,
  created_by uuid references auth.users(id)
);

create index if not exists idx_submissions_form_id on submissions(form_id);
create index if not exists idx_submissions_geom on submissions using gist(geom);

alter table submissions enable row level security;

-- Starting policy: any authenticated field worker can insert/upsert their
-- own records and read everything (tighten per-team/per-project once you
-- have multiple crews or need row-level visibility restrictions).
create policy "Authenticated users can upsert submissions"
  on submissions for insert
  to authenticated
  with check (true);

create policy "Authenticated users can update their own submissions"
  on submissions for update
  to authenticated
  using (created_by = auth.uid() or created_by is null);

create policy "Authenticated users can read all submissions"
  on submissions for select
  to authenticated
  using (true);
