# Field Monitor — offline-first ecological survey app

A Flutter skeleton for the RHA app we scoped: a dynamic, JSON-schema-driven
form engine, offline local storage, GPS capture, and background sync to
Supabase (Postgres + PostGIS).

## What's here

```
lib/
  models/form_schema.dart          Parses JSON form schemas, evaluates
                                    conditional visibility + computed fields
  data/app_database.dart           sqflite local store (submissions table)
  services/location_service.dart   GPS capture via geolocator
  services/sync_service.dart       Connectivity-triggered upload to Supabase
  ui/widgets/dynamic_form_renderer.dart
                                    The engine — renders any FormSchema
  ui/screens/
    home_screen.dart               Form catalogue + sync status
    form_screen.dart               Loads a schema, hosts the renderer, saves
    record_list_screen.dart        Local records with sync status
  main.dart                        App entry, Supabase init
assets/schemas/rha_v1.json         Draft RHA schema (see caveat below)
supabase/schema.sql                Postgres/PostGIS table + RLS policies
```

## Setup

1. Install Flutter (3.22+) and run `flutter pub get` from this directory.
2. Create a Supabase project, enable the PostGIS extension, then run
   `supabase/schema.sql` in the SQL editor.
3. Run with your project's keys:
   ```
   flutter run \
     --dart-define=SUPABASE_URL=https://your-project.supabase.co \
     --dart-define=SUPABASE_ANON_KEY=your-anon-key
   ```
4. iOS: add `NSLocationWhenInUseUsageDescription` and
   `NSCameraUsageDescription` to `ios/Runner/Info.plist`.
   Android: `ACCESS_FINE_LOCATION` and `CAMERA` permissions in
   `android/app/src/main/AndroidManifest.xml`. (Platform folders aren't
   included in this skeleton — run `flutter create .` in this directory
   first to generate them, then add these entries.)

## About the RHA schema

`assets/schemas/rha_v1.json` is a **draft**, built from the general
structure of Cawthron's RHA protocol (9 scored parameters, P1–P9, summing
to a score out of 100) — I wasn't able to fetch the actual field sheet PDF
(it blocks automated access), so I reconstructed the parameter list from
published summaries rather than the source document. Before field use:

- Check each parameter's exact wording, scoring band (1–10 vs 1–20), and
  order against your team's official RHA sheet
- Adjust `min`/`max` on each `scale` field to match
- Add any parameters I've missed or merged

This is exactly the kind of correction the JSON-schema approach makes
cheap — no app rebuild, just edit the file.

## Extending with new monitoring types

1. Write a new JSON schema (copy `rha_v1.json` as a starting point) — see
   `lib/models/form_schema.dart` for the field types available
   (`text`, `textarea`, `number`, `date`, `select_one`, `select_many`,
   `scale`, `geopoint`, `photo`, `computed`)
2. Drop it in `assets/schemas/`, add the path to `pubspec.yaml` assets if
   it's a new directory
3. Add one `FormCatalogueEntry` in `lib/ui/screens/home_screen.dart`

No new screens, no new storage code — `submissions.form_id` /
`form_version` already distinguish record types, and the local DB schema
is intentionally form-agnostic (answers live in a `data` JSON column).

## Known gaps in this skeleton (intentional — next steps, not oversights)

- **`geoshape`/`geotrace` fields** (site boundary polygons, transect
  tracks) render as a placeholder — worth a `flutter_map` drawing overlay
  when you need them.
- **`repeat` field type** (e.g. "add another transect") is parsed but not
  rendered yet.
- **Offline basemap tiles**: `flutter_map` is wired in as a dependency but
  no tile caching is implemented — add an MBTiles/vector-tile package and
  a "download this area" flow before relying on it in zero-signal terrain.
- **Photo upload to Supabase Storage**: sync currently pushes the `data`
  JSON (which includes local file paths) but doesn't yet upload the image
  bytes — add that step in `sync_service.dart` alongside the record push.
- **Device ID**: `form_screen.dart` uses a placeholder string — swap in a
  persisted UUID (e.g. via `shared_preferences`, generated once on first
  launch) so records are attributable to a device/user.
- **Auth**: Supabase client is initialized but nothing signs a user in yet
  — add Supabase email/magic-link or SSO auth before relying on the RLS
  policies in `schema.sql`.
- **Conflict resolution**: sync is last-write-wins via `upsert` — fine for
  this domain (field records are rarely edited by two people at once), but
  worth a deliberate look if your team's workflow changes.
