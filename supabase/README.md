# Backend (Supabase)

The page in this repo is only a client. Everything else the app needs lives in the Supabase
project `sobshyactzxhtsayemkj`: the database, sign-in, the photo bucket and three Edge Functions.
This folder mirrors the **code** of that backend so a clone can rebuild it. It holds no data.

```
supabase/
  functions/
    identify-item/index.ts     photo(s) of one garment -> draft item + receipt candidates + possible duplicates
    identify-outfit/index.ts   one selfie -> visible garments, each with ranked closet candidates
    import-photo/index.ts      pulls a retailer product image by URL into the photo bucket
  schema.sql                   schema only: enums, tables, constraints, indexes, views, RLS + storage policies, SQL function
  README.md                    this file
```

## What is deployed

Captured 12 Nov 2026. Each file is the source the Supabase API returns for the deployed version.

| Function | Deployed version | verify_jwt | Calls the Claude API | Writes |
| --- | --- | --- | --- | --- |
| `identify-item` | 6 | on | yes | nothing |
| `identify-outfit` | 2 | on | yes | nothing |
| `import-photo` | 2 | on | no | one storage object, and the item's cover fields |

All three answer `POST` only, run as the calling user (the user's token, never the service-role key),
and send `Access-Control-Allow-Origin: https://joegrimaldi.github.io`. If the page ever moves to
another origin, that header must change in all three files.

`schema.sql` reflects the database after migration `20261113032047`. Applied migrations, oldest first:

| Version | Name |
| --- | --- |
| 20260823161318 | create_item_photos_bucket |
| 20260929172104 | add_teams_lookup |
| 20260930015727 | trip_occasions_and_occasion_items |
| 20260930033610 | swatch_and_location |
| 20260930035817 | outfits_photo_ref |
| 20260930040214 | teams_include_bands |
| 20261001024946 | acquisitions_claim_status |
| 20261112202708 | item_photos_read_authenticated_only |
| 20261112204359 | tmp_backup_export_open |
| 20261112204430 | tmp_backup_export_close |
| 20261113030339 | item_photos_bucket_private |
| 20261113031427 | owner_scoped_rls |
| 20261113031447 | revoke_rls_auto_enable_execute |
| 20261113032047 | atomic_outfit_writes |

The earliest tables were created before migrations were used, so the migrations alone do not rebuild
the schema. `schema.sql` does. It supersedes the project document `schema.sql` (v1), which is stale.

## How these files were captured

- **Functions:** from the Supabase management API (the connector's "get Edge Function" call), which
  returns the deployed source. `supabase functions download <name> --project-ref sobshyactzxhtsayemkj`
  returns the same thing and is the way to re-check them.
- **Schema:** generated from the live system catalogs through the SQL connector, because the
  maintaining Mac has no Supabase CLI, `pg_dump` or Docker. The generated text was checksummed inside
  the database and the committed copy matches it byte for byte. It is not `pg_dump` output; the header
  of `schema.sql` lists what that means. With the CLI available, `supabase db dump --schema public`
  (schema only is its default) plus the `storage.objects` policies is the equivalent.

## Deploying a function

Edit the file here first, commit, then deploy that exact file:

```bash
supabase functions deploy identify-outfit --project-ref sobshyactzxhtsayemkj
```

(`verify_jwt` stays on, which is the default.) The Supabase connector's deploy call does the same job.
Afterwards update the version table above. Never deploy something that is not committed: the repo and
the deployed function drifting apart is the failure this folder exists to prevent.

## Secrets and settings that are not in this repo

- `ANTHROPIC_API_KEY` (required by the two identify functions) and `ANTHROPIC_MODEL` (optional
  override) are Supabase function secrets. They exist only in Supabase.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` are injected into functions by the platform.
- The database credentials and any connection string are never written to this repo.
  The publishable key in `index.html` is public by design.
- Dashboard settings that no SQL captures: Auth sign-up is **disabled** (12 Nov 2026); the
  `item-photos` bucket is **private** since 13 Nov 2026 (photos load only through signed URLs; see `photoUrl()` in `index.html`), 10 MB limit, images only (see the Storage section of `schema.sql`).

## What must never be added here

This repository is public. No rows, no `INSERT`s or seed files, no photos, no receipts, no backups.
Data backups live in private storage.
