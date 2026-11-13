-- Wardrobe tracker: database schema (schema only, no row data)
-- Supabase project sobshyactzxhtsayemkj. Captured 2026-11-12, after migration
-- 20261112204430 (tmp_backup_export_close). Hand-updated 2026-11-13 for the
-- migrations listed in README.md through revoke_rls_auto_enable_execute
-- (private bucket, owner-scoped policies, revoked EXECUTE); the md5 below refers
-- to the 2026-11-12 capture.
--
-- How this file was made: generated from the live system catalogs
-- (pg_get_constraintdef, pg_get_viewdef, pg_get_functiondef, pg_policies, ...)
-- through the Supabase SQL connector. It is NOT pg_dump output: the Mac that
-- maintains this repo has no Supabase CLI, pg_dump or Docker. The text below the
-- header was checksummed in the database and matches byte for byte
-- (md5 98d08864ea594ee23610b7dc70f631a2, 23,625 bytes).
--
-- Scope: everything the app owns in schema `public` (enums, tables, constraints,
-- indexes, comments, views, the one SQL function and its event trigger, row-level
-- security, table privileges) plus the storage policies on storage.objects.
-- Not included: Supabase-managed schemas (auth, storage internals, vault,
-- extensions), object ownership, default privileges, and any rows.
--
-- Reading notes:
--   * Names inside constraint, view and trigger bodies are unqualified, as Postgres
--     prints them; they resolve with search_path = public (the default).
--   * Row-level security is on for all 11 tables. Every table policy and every
--     storage policy is scoped to one account: auth.uid() must equal Joe's user id
--     (owner_scoped_rls, 13 Nov 2026). Sign-up is also disabled in Supabase Auth
--     (a dashboard setting, not SQL). A new account would see nothing.
--   * anon holds table privileges (Supabase's default grants) but no policy, so
--     anonymous requests see nothing.
--   * rls_auto_enable() only runs as an event trigger; EXECUTE is revoked from
--     PUBLIC, anon and authenticated.
--   * The bucket itself is configuration, shown as a comment in the Storage section.
--
-- This file supersedes the project document "schema.sql" (v1), which predates
-- trips, teams, swatches, locations, outfit photos and receipt claim status.

-- Postgres 17.6
-- Installed extensions (managed by Supabase):
--   pg_stat_statements 1.11 (schema extensions)
--   pgcrypto 1.3 (schema extensions)
--   plpgsql 1.0 (schema pg_catalog)
--   supabase_vault 0.3.1 (schema vault)
--   uuid-ossp 1.1 (schema extensions)

-- ===== Enum types =====
CREATE TYPE public.acquired_how AS ENUM ('bought', 'gift', 'inherited', 'unknown');
CREATE TYPE public.care_type AS ENUM ('wash', 'dry_clean', 'repair', 'alteration', 'polish', 'other');
CREATE TYPE public.item_class AS ENUM ('wardrobe', 'collectible', 'property');
CREATE TYPE public.item_status AS ENUM ('active', 'stored', 'repair', 'donated', 'sold', 'lost');
CREATE TYPE public.layer_type AS ENUM ('shirt', 'pants', 'outer', 'shoes', 'accessory', 'other');
CREATE TYPE public.outfit_slot AS ENUM ('primary', 'evening', 'gym', 'bed', 'travel');
CREATE TYPE public.weight_class AS ENUM ('light', 'mid', 'heavy');

-- ===== Tables =====
CREATE TABLE public.acquisitions (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  retailer text,
  order_ref text,
  order_date date,
  item_description text,
  unit_price numeric(10,2),
  quantity integer,
  currency text DEFAULT 'USD'::text NOT NULL,
  raw_source text,
  matched_item_id bigint,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  claim_status text,
  claim_note text
);

CREATE TABLE public.care_events (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  item_id bigint,
  event_type care_type NOT NULL,
  event_date date NOT NULL,
  cost numeric(10,2),
  vendor text,
  notes text,
  source text,
  source_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.categories (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  parent_id bigint,
  default_layer layer_type,
  size_format text,
  sort_order integer DEFAULT 0 NOT NULL
);

CREATE TABLE public.collectible_attrs (
  item_id bigint NOT NULL,
  player_name text,
  name_on_back text,
  uniform_number text,
  city text,
  team text,
  season_year integer,
  provenance text
);

CREATE TABLE public.items (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  item_class item_class DEFAULT 'wardrobe'::item_class NOT NULL,
  category_id bigint,
  layer layer_type,
  brand text,
  colors text[] DEFAULT '{}'::text[] NOT NULL,
  pattern text,
  material text,
  size text,
  fit text,
  formality smallint,
  season_tags text[] DEFAULT '{}'::text[] NOT NULL,
  weight weight_class,
  quantity integer DEFAULT 1 NOT NULL,
  unit_price numeric(10,2),
  replacement_value numeric(10,2),
  purchase_date date,
  retailer text,
  acquired_how acquired_how DEFAULT 'unknown'::acquired_how,
  condition smallint,
  status item_status DEFAULT 'active'::item_status NOT NULL,
  location text,
  parent_item_id bigint,
  photo_ref text,
  care_instructions text,
  notes text,
  source text,
  source_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  retired_at date,
  price_source text,
  photo_source text,
  team_id bigint,
  swatch_hex text,
  swatch_source text
);

CREATE TABLE public.occasion_items (
  occasion_id bigint NOT NULL,
  item_id bigint NOT NULL,
  role text
);

CREATE TABLE public.outfit_items (
  outfit_id bigint NOT NULL,
  item_id bigint NOT NULL,
  role text
);

CREATE TABLE public.outfits (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text,
  worn_on date NOT NULL,
  slot outfit_slot DEFAULT 'primary'::outfit_slot NOT NULL,
  occasion text,
  trip_id bigint,
  weather_high numeric(4,1),
  weather_low numeric(4,1),
  precip text,
  calendar_context text,
  self_rating smallint,
  notes text,
  source text,
  source_id text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  photo_ref text
);

CREATE TABLE public.teams (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  league text,
  sort_order integer DEFAULT 0 NOT NULL,
  kind text DEFAULT 'team'::text NOT NULL
);

CREATE TABLE public.trip_occasions (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  trip_id bigint NOT NULL,
  occasion_date date NOT NULL,
  slot outfit_slot DEFAULT 'primary'::outfit_slot NOT NULL,
  name text NOT NULL,
  dress_code text,
  formality_min smallint,
  formality_max smallint,
  excluded_category_ids bigint[] DEFAULT '{}'::bigint[] NOT NULL,
  weather_high numeric(4,1),
  weather_low numeric(4,1),
  precip text,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.trips (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  name text NOT NULL,
  start_date date,
  end_date date,
  destination text,
  notes text,
  created_at timestamp with time zone DEFAULT now() NOT NULL
);

-- ===== Primary keys, unique, check and foreign-key constraints =====
ALTER TABLE ONLY public.acquisitions ADD CONSTRAINT acquisitions_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.care_events ADD CONSTRAINT care_events_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.categories ADD CONSTRAINT categories_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.collectible_attrs ADD CONSTRAINT collectible_attrs_pkey PRIMARY KEY (item_id);
ALTER TABLE ONLY public.items ADD CONSTRAINT items_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.occasion_items ADD CONSTRAINT occasion_items_pkey PRIMARY KEY (occasion_id, item_id);
ALTER TABLE ONLY public.outfit_items ADD CONSTRAINT outfit_items_pkey PRIMARY KEY (outfit_id, item_id);
ALTER TABLE ONLY public.outfits ADD CONSTRAINT outfits_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.teams ADD CONSTRAINT teams_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.trip_occasions ADD CONSTRAINT trip_occasions_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.trips ADD CONSTRAINT trips_pkey PRIMARY KEY (id);
ALTER TABLE ONLY public.care_events ADD CONSTRAINT care_events_source_source_id_key UNIQUE (source, source_id);
ALTER TABLE ONLY public.categories ADD CONSTRAINT categories_name_parent_id_key UNIQUE (name, parent_id);
ALTER TABLE ONLY public.items ADD CONSTRAINT items_source_source_id_key UNIQUE (source, source_id);
ALTER TABLE ONLY public.outfits ADD CONSTRAINT outfits_source_source_id_key UNIQUE (source, source_id);
ALTER TABLE ONLY public.outfits ADD CONSTRAINT outfits_worn_on_slot_key UNIQUE (worn_on, slot);
ALTER TABLE ONLY public.teams ADD CONSTRAINT teams_name_key UNIQUE (name);
ALTER TABLE ONLY public.trip_occasions ADD CONSTRAINT trip_occasions_trip_id_occasion_date_slot_key UNIQUE (trip_id, occasion_date, slot);
ALTER TABLE ONLY public.acquisitions ADD CONSTRAINT acquisitions_claim_status_check CHECK ((claim_status = ANY (ARRAY['owned'::text, 'not_owned'::text, 'unsure'::text, 'duplicate'::text, 'not_clothing'::text])));
ALTER TABLE ONLY public.care_events ADD CONSTRAINT care_events_cost_check CHECK ((cost >= (0)::numeric));
ALTER TABLE ONLY public.collectible_attrs ADD CONSTRAINT collectible_attrs_season_year_check CHECK (((season_year >= 1900) AND (season_year <= 2100)));
ALTER TABLE ONLY public.items ADD CONSTRAINT item_not_own_parent CHECK (((parent_item_id IS NULL) OR (parent_item_id <> id)));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_condition_check CHECK (((condition >= 1) AND (condition <= 5)));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_formality_check CHECK (((formality >= 1) AND (formality <= 5)));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_location_check CHECK (((location IS NULL) OR (location = ANY (ARRAY['Coat rack'::text, 'Shoe rack'::text, 'Basket'::text, 'Dresser'::text, 'Closet'::text, 'Cedar chest'::text, 'Bureau'::text, 'Storage unit'::text]))));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_quantity_check CHECK ((quantity > 0));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_replacement_value_check CHECK ((replacement_value >= (0)::numeric));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_swatch_hex_check CHECK ((swatch_hex ~ '^#[0-9A-F]{6}$'::text));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_swatch_source_check CHECK ((swatch_source = ANY (ARRAY['name'::text, 'photo'::text])));
ALTER TABLE ONLY public.items ADD CONSTRAINT items_unit_price_check CHECK ((unit_price >= (0)::numeric));
ALTER TABLE ONLY public.outfits ADD CONSTRAINT outfits_self_rating_check CHECK (((self_rating >= 1) AND (self_rating <= 5)));
ALTER TABLE ONLY public.teams ADD CONSTRAINT teams_kind_check CHECK ((kind = ANY (ARRAY['team'::text, 'band'::text])));
ALTER TABLE ONLY public.trip_occasions ADD CONSTRAINT trip_occasions_check CHECK (((formality_min IS NULL) OR (formality_max IS NULL) OR (formality_min <= formality_max)));
ALTER TABLE ONLY public.trip_occasions ADD CONSTRAINT trip_occasions_formality_max_check CHECK (((formality_max >= 1) AND (formality_max <= 5)));
ALTER TABLE ONLY public.trip_occasions ADD CONSTRAINT trip_occasions_formality_min_check CHECK (((formality_min >= 1) AND (formality_min <= 5)));
ALTER TABLE ONLY public.trips ADD CONSTRAINT trips_check CHECK (((end_date IS NULL) OR (start_date IS NULL) OR (end_date >= start_date)));
ALTER TABLE ONLY public.acquisitions ADD CONSTRAINT acquisitions_matched_item_id_fkey FOREIGN KEY (matched_item_id) REFERENCES items(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.care_events ADD CONSTRAINT care_events_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.categories ADD CONSTRAINT categories_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES categories(id) ON DELETE RESTRICT;
ALTER TABLE ONLY public.collectible_attrs ADD CONSTRAINT collectible_attrs_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.items ADD CONSTRAINT items_category_id_fkey FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.items ADD CONSTRAINT items_parent_item_id_fkey FOREIGN KEY (parent_item_id) REFERENCES items(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.items ADD CONSTRAINT items_team_id_fkey FOREIGN KEY (team_id) REFERENCES teams(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.occasion_items ADD CONSTRAINT occasion_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.occasion_items ADD CONSTRAINT occasion_items_occasion_id_fkey FOREIGN KEY (occasion_id) REFERENCES trip_occasions(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.outfit_items ADD CONSTRAINT outfit_items_item_id_fkey FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.outfit_items ADD CONSTRAINT outfit_items_outfit_id_fkey FOREIGN KEY (outfit_id) REFERENCES outfits(id) ON DELETE CASCADE;
ALTER TABLE ONLY public.outfits ADD CONSTRAINT outfits_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE SET NULL;
ALTER TABLE ONLY public.trip_occasions ADD CONSTRAINT trip_occasions_trip_id_fkey FOREIGN KEY (trip_id) REFERENCES trips(id) ON DELETE CASCADE;

-- ===== Indexes (other than those backing constraints) =====
CREATE INDEX acquisitions_matched_item_id_idx ON public.acquisitions USING btree (matched_item_id);
CREATE INDEX care_events_event_date_idx ON public.care_events USING btree (event_date DESC);
CREATE INDEX care_events_item_id_idx ON public.care_events USING btree (item_id);
CREATE INDEX items_category_id_idx ON public.items USING btree (category_id);
CREATE INDEX items_item_class_idx ON public.items USING btree (item_class);
CREATE INDEX items_layer_idx ON public.items USING btree (layer);
CREATE INDEX items_parent_item_id_idx ON public.items USING btree (parent_item_id);
CREATE INDEX items_status_idx ON public.items USING btree (status);
CREATE INDEX items_team_id_idx ON public.items USING btree (team_id);
CREATE INDEX occasion_items_item_id_idx ON public.occasion_items USING btree (item_id);
CREATE INDEX outfit_items_item_id_idx ON public.outfit_items USING btree (item_id);
CREATE INDEX outfits_trip_id_idx ON public.outfits USING btree (trip_id);
CREATE INDEX outfits_worn_on_idx ON public.outfits USING btree (worn_on DESC);
CREATE INDEX trip_occasions_occasion_date_idx ON public.trip_occasions USING btree (occasion_date);

-- ===== Comments =====
COMMENT ON COLUMN public.acquisitions.claim_status IS 'Joe''s answer in the claim pass: owned (item created/linked), not_owned (returned/gone/never had), unsure, duplicate (same line parked twice), not_clothing. NULL = not yet reviewed.';
COMMENT ON COLUMN public.items.location IS 'Where it lives. NULL = at home, spot not yet recorded. Only Storage unit is excluded from trip planning.';
COMMENT ON COLUMN public.items.price_source IS 'receipt | catalog_list | manual | estimate | unknown. UI renders estimate-sourced prices and metrics with a ~ prefix.';
COMMENT ON COLUMN public.items.photo_source IS 'own_photo | retailer | none';
COMMENT ON COLUMN public.items.team_id IS 'Set when the item is team gear (jersey, Starter jacket, scarf). Filters team gear out of general rotation metrics.';
COMMENT ON COLUMN public.items.swatch_hex IS 'Dominant colour of the item. Recalculated from the cover photo whenever the cover changes; used for list display and future colour-based recommendations.';
COMMENT ON COLUMN public.items.swatch_source IS 'name = estimated from the colour name; photo = sampled from the current cover photo.';
COMMENT ON TABLE public.occasion_items IS 'PLANNED outfit per occasion. Never counted as a wear; worn outfits live in outfits/outfit_items. Packing list = distinct item_id across a trip''s occasions.';
COMMENT ON COLUMN public.outfits.photo_ref IS 'Outfit selfie: object path in the item-photos bucket, e.g. outfits/2026-10-05-evening.jpg. NULL = no photo.';
COMMENT ON COLUMN public.teams.kind IS 'team = sports team, band = music act. Both mark fan gear, which is kept out of general rotation metrics.';
COMMENT ON TABLE public.trip_occasions IS 'Itinerary: one row per time you get dressed for something on a trip. Matches outfits on (occasion_date, slot) = (worn_on, slot).';

-- ===== Views =====
CREATE VIEW public.v_item_wear_stats WITH (security_invoker=on) AS
 SELECT i.id,
    i.name,
    i.item_class,
    i.layer,
    i.brand,
    i.quantity,
    i.status,
    count(oi.outfit_id) AS total_wears,
    round(count(oi.outfit_id)::numeric / i.quantity::numeric, 2) AS wears_per_unit,
    count(oi.outfit_id) FILTER (WHERE o.worn_on >= (CURRENT_DATE - 90)) AS wears_90d,
    count(oi.outfit_id) FILTER (WHERE o.worn_on >= (CURRENT_DATE - 365)) AS wears_365d,
    max(o.worn_on) AS last_worn,
    CURRENT_DATE - max(o.worn_on) AS days_since_last_worn,
    COALESCE(i.unit_price, 0::numeric) * i.quantity::numeric AS purchase_outlay,
    COALESCE(care.total_cost, 0::numeric) AS care_cost,
    COALESCE(i.unit_price, 0::numeric) * i.quantity::numeric + COALESCE(care.total_cost, 0::numeric) AS true_cost,
        CASE
            WHEN count(oi.outfit_id) > 0 THEN round((COALESCE(i.unit_price, 0::numeric) * i.quantity::numeric + COALESCE(care.total_cost, 0::numeric)) / count(oi.outfit_id)::numeric, 2)
            ELSE NULL::numeric
        END AS cost_per_wear
   FROM items i
     LEFT JOIN outfit_items oi ON oi.item_id = i.id
     LEFT JOIN outfits o ON o.id = oi.outfit_id
     LEFT JOIN LATERAL ( SELECT sum(ce.cost) AS total_cost
           FROM care_events ce
          WHERE ce.item_id = i.id) care ON true
  GROUP BY i.id, care.total_cost;

CREATE VIEW public.v_dead_stock WITH (security_invoker=on) AS
 SELECT id,
    name,
    item_class,
    layer,
    brand,
    quantity,
    status,
    total_wears,
    wears_per_unit,
    wears_90d,
    wears_365d,
    last_worn,
    days_since_last_worn,
    purchase_outlay,
    care_cost,
    true_cost,
    cost_per_wear
   FROM v_item_wear_stats
  WHERE item_class = 'wardrobe'::item_class AND status = 'active'::item_status AND COALESCE(wears_365d, 0::bigint) = 0
  ORDER BY true_cost DESC NULLS LAST;

CREATE VIEW public.v_closet_utilisation WITH (security_invoker=on) AS
 SELECT count(*) AS active_items,
    count(*) FILTER (WHERE wears_90d > 0) AS worn_90d,
    round(100.0 * count(*) FILTER (WHERE wears_90d > 0)::numeric / NULLIF(count(*), 0)::numeric, 1) AS pct_worn_90d,
    sum(true_cost) FILTER (WHERE COALESCE(wears_365d, 0::bigint) = 0) AS idle_capital
   FROM v_item_wear_stats
  WHERE item_class = 'wardrobe'::item_class AND status = 'active'::item_status;

CREATE VIEW public.v_pair_affinity WITH (security_invoker=on) AS
 SELECT a.item_id AS item_a,
    b.item_id AS item_b,
    count(*) AS times_worn_together
   FROM outfit_items a
     JOIN outfit_items b ON a.outfit_id = b.outfit_id AND a.item_id < b.item_id
  GROUP BY a.item_id, b.item_id;

-- ===== SQL functions =====
CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$
;
-- EXECUTE on public.rls_auto_enable() is held by: postgres, service_role (revoked from PUBLIC, anon, authenticated in migration 20261113031447)

-- ===== Triggers =====
-- none

-- ===== Event triggers =====
CREATE EVENT TRIGGER ensure_rls ON ddl_command_end
  WHEN TAG IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
  EXECUTE FUNCTION rls_auto_enable();

-- ===== Row-level security =====
ALTER TABLE public.acquisitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.care_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.collectible_attrs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.occasion_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outfit_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outfits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trip_occasions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trips ENABLE ROW LEVEL SECURITY;

CREATE POLICY owner_full_access ON public.acquisitions AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.care_events AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.categories AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.collectible_attrs AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.items AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.occasion_items AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.outfit_items AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.outfits AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.teams AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.trip_occasions AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));
CREATE POLICY owner_full_access ON public.trips AS PERMISSIVE FOR ALL TO authenticated
  USING ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid))
  WITH CHECK ((( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid));

-- ===== Table privileges (Supabase API roles) =====
GRANT ALL ON TABLE public.acquisitions TO anon;
GRANT ALL ON TABLE public.acquisitions TO authenticated;
GRANT ALL ON TABLE public.acquisitions TO service_role;
GRANT ALL ON TABLE public.care_events TO anon;
GRANT ALL ON TABLE public.care_events TO authenticated;
GRANT ALL ON TABLE public.care_events TO service_role;
GRANT ALL ON TABLE public.categories TO anon;
GRANT ALL ON TABLE public.categories TO authenticated;
GRANT ALL ON TABLE public.categories TO service_role;
GRANT ALL ON TABLE public.collectible_attrs TO anon;
GRANT ALL ON TABLE public.collectible_attrs TO authenticated;
GRANT ALL ON TABLE public.collectible_attrs TO service_role;
GRANT ALL ON TABLE public.items TO anon;
GRANT ALL ON TABLE public.items TO authenticated;
GRANT ALL ON TABLE public.items TO service_role;
GRANT ALL ON TABLE public.occasion_items TO anon;
GRANT ALL ON TABLE public.occasion_items TO authenticated;
GRANT ALL ON TABLE public.occasion_items TO service_role;
GRANT ALL ON TABLE public.outfit_items TO anon;
GRANT ALL ON TABLE public.outfit_items TO authenticated;
GRANT ALL ON TABLE public.outfit_items TO service_role;
GRANT ALL ON TABLE public.outfits TO anon;
GRANT ALL ON TABLE public.outfits TO authenticated;
GRANT ALL ON TABLE public.outfits TO service_role;
GRANT ALL ON TABLE public.teams TO anon;
GRANT ALL ON TABLE public.teams TO authenticated;
GRANT ALL ON TABLE public.teams TO service_role;
GRANT ALL ON TABLE public.trip_occasions TO anon;
GRANT ALL ON TABLE public.trip_occasions TO authenticated;
GRANT ALL ON TABLE public.trip_occasions TO service_role;
GRANT ALL ON TABLE public.trips TO anon;
GRANT ALL ON TABLE public.trips TO authenticated;
GRANT ALL ON TABLE public.trips TO service_role;
GRANT ALL ON TABLE public.v_closet_utilisation TO anon;
GRANT ALL ON TABLE public.v_closet_utilisation TO authenticated;
GRANT ALL ON TABLE public.v_closet_utilisation TO service_role;
GRANT ALL ON TABLE public.v_dead_stock TO anon;
GRANT ALL ON TABLE public.v_dead_stock TO authenticated;
GRANT ALL ON TABLE public.v_dead_stock TO service_role;
GRANT ALL ON TABLE public.v_item_wear_stats TO anon;
GRANT ALL ON TABLE public.v_item_wear_stats TO authenticated;
GRANT ALL ON TABLE public.v_item_wear_stats TO service_role;
GRANT ALL ON TABLE public.v_pair_affinity TO anon;
GRANT ALL ON TABLE public.v_pair_affinity TO authenticated;
GRANT ALL ON TABLE public.v_pair_affinity TO service_role;

-- ===== Storage =====
-- Buckets (configuration, created by migration create_item_photos_bucket; not row data):
--   item-photos: public=f (private since migration 20261113030339; was public=t), file_size_limit=10485760 bytes, allowed_mime_types={image/png,image/jpeg,image/webp,image/avif}
-- storage.objects has row-level security enabled by the platform. Policies:
CREATE POLICY item_photos_owner_delete ON storage.objects AS PERMISSIVE FOR DELETE TO authenticated
  USING (((bucket_id = 'item-photos'::text) AND (( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid)));
CREATE POLICY item_photos_owner_read ON storage.objects AS PERMISSIVE FOR SELECT TO authenticated
  USING (((bucket_id = 'item-photos'::text) AND (( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid)));
CREATE POLICY item_photos_owner_update ON storage.objects AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((bucket_id = 'item-photos'::text) AND (( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid)))
  WITH CHECK (((bucket_id = 'item-photos'::text) AND (( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid)));
CREATE POLICY item_photos_owner_write ON storage.objects AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((bucket_id = 'item-photos'::text) AND (( SELECT auth.uid() AS uid) = '57e1da5a-e8b1-4f63-a5c3-7750cd494026'::uuid)));
