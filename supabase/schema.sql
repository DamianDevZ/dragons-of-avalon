-- =============================================================================
-- Dragons of Avalon — Initial Database Schema
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
-- =============================================================================
-- Design principles:
--   • All resource math is done server-side via Edge Functions using delta-time.
--     Resource columns store "last saved" amounts, not live totals.
--   • Row Level Security (RLS) ensures players can only read/write their own
--     data. World map tiles are readable by all but writable only via RPC.
--   • UUIDs everywhere for player IDs (matches Supabase Auth user IDs).
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------------------
-- PLAYERS
-- Linked 1-to-1 with auth.users. Created automatically on first sign-in
-- via a database trigger (see bottom of file).
-- ---------------------------------------------------------------------------

CREATE TABLE public.players (
    id               UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name     TEXT        NOT NULL UNIQUE,
    castle_level     SMALLINT    NOT NULL DEFAULT 1,
    -- expansion_cap grows with castle_level; calculated by trigger on castle upgrade.
    expansion_cap    SMALLINT    NOT NULL DEFAULT 5,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;
-- Players can read their own row; world-map lookups will use a separate view.
CREATE POLICY "players: owner read/write" ON public.players
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);


-- ---------------------------------------------------------------------------
-- PLAYER_RESOURCES
-- Stores the last-saved snapshot. The calculate_resources Edge Function
-- projects forward using: current = saved + (rate × elapsed_seconds).
-- ---------------------------------------------------------------------------

CREATE TABLE public.player_resources (
    player_id           UUID        PRIMARY KEY REFERENCES public.players(id) ON DELETE CASCADE,
    wood                NUMERIC     NOT NULL DEFAULT 0,
    food                NUMERIC     NOT NULL DEFAULT 0,
    stone               NUMERIC     NOT NULL DEFAULT 0,
    gold                NUMERIC     NOT NULL DEFAULT 0,
    -- Timestamp of the last time this row was written (= "time zero" for delta calc).
    last_calculated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.player_resources ENABLE ROW LEVEL SECURITY;
CREATE POLICY "resources: owner only" ON public.player_resources
    USING (auth.uid() = player_id)
    WITH CHECK (auth.uid() = player_id);


-- ---------------------------------------------------------------------------
-- WORLD_TILES
-- The shared map. X/Y are integer coordinates. Tile types determine which
-- buildings get a production bonus when placed here.
-- occupied_by is NULL for unclaimed tiles.
-- ---------------------------------------------------------------------------

CREATE TYPE tile_type_enum AS ENUM ('field', 'forest', 'mountain', 'lake', 'ruins', 'volcano');

CREATE TABLE public.world_tiles (
    x            INTEGER          NOT NULL,
    y            INTEGER          NOT NULL,
    tile_type    tile_type_enum   NOT NULL DEFAULT 'field',
    occupied_by  UUID             REFERENCES public.players(id) ON DELETE SET NULL,
    occupied_at  TIMESTAMPTZ,
    PRIMARY KEY (x, y)
);

ALTER TABLE public.world_tiles ENABLE ROW LEVEL SECURITY;
-- Everyone can view the map.
CREATE POLICY "world_tiles: public read" ON public.world_tiles
    FOR SELECT USING (true);
-- Only the occupying player can mark a tile as theirs — enforced via RPC,
-- not direct UPDATE, so this policy intentionally blocks direct writes.
CREATE POLICY "world_tiles: no direct write" ON public.world_tiles
    FOR ALL USING (false);


-- ---------------------------------------------------------------------------
-- CITY_BUILDINGS
-- Buildings inside the player's private city grid.
-- grid_x / grid_y are positions within the city canvas.
-- ---------------------------------------------------------------------------

CREATE TYPE building_type_enum AS ENUM (
    'castle', 'lumber_mill', 'farm', 'quarry', 'gold_mine',
    'barracks', 'stable', 'dragon_roost', 'wall', 'market', 'storehouse'
);

CREATE TABLE public.city_buildings (
    id           UUID             PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id    UUID             NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    building_type building_type_enum NOT NULL,
    level        SMALLINT         NOT NULL DEFAULT 1,
    grid_x       SMALLINT         NOT NULL,
    grid_y       SMALLINT         NOT NULL,
    -- NULL means the building is complete; future timestamp means upgrading.
    upgrade_complete_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ      NOT NULL DEFAULT NOW(),
    UNIQUE (player_id, grid_x, grid_y)
);

ALTER TABLE public.city_buildings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "city_buildings: owner only" ON public.city_buildings
    USING (auth.uid() = player_id)
    WITH CHECK (auth.uid() = player_id);


-- ---------------------------------------------------------------------------
-- TILE_BUILDINGS
-- Resource-gathering buildings placed on occupied world-map tiles.
-- Matching building type to tile type grants a production bonus (handled
-- in the calculate_resources Edge Function).
-- ---------------------------------------------------------------------------

CREATE TABLE public.tile_buildings (
    id            UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id     UUID              NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    tile_x        INTEGER           NOT NULL,
    tile_y        INTEGER           NOT NULL,
    building_type building_type_enum NOT NULL,
    level         SMALLINT          NOT NULL DEFAULT 1,
    upgrade_complete_at TIMESTAMPTZ,
    FOREIGN KEY (tile_x, tile_y) REFERENCES public.world_tiles(x, y),
    -- One building per tile per player (enforced; tile is already exclusively theirs).
    UNIQUE (player_id, tile_x, tile_y)
);

ALTER TABLE public.tile_buildings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "tile_buildings: owner only" ON public.tile_buildings
    USING (auth.uid() = player_id)
    WITH CHECK (auth.uid() = player_id);


-- ---------------------------------------------------------------------------
-- DRAGONS
-- ---------------------------------------------------------------------------

CREATE TYPE dragon_rarity_enum AS ENUM ('common', 'uncommon', 'rare', 'legendary');

CREATE TABLE public.dragons (
    id           UUID              PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id    UUID              NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    name         TEXT              NOT NULL,
    rarity       dragon_rarity_enum NOT NULL DEFAULT 'common',
    level        SMALLINT          NOT NULL DEFAULT 1,
    experience   INTEGER           NOT NULL DEFAULT 0,
    -- NULL = still in the egg (hatch_complete_at is when it hatches).
    hatch_complete_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ       NOT NULL DEFAULT NOW()
);

ALTER TABLE public.dragons ENABLE ROW LEVEL SECURITY;
CREATE POLICY "dragons: owner only" ON public.dragons
    USING (auth.uid() = player_id)
    WITH CHECK (auth.uid() = player_id);


-- ---------------------------------------------------------------------------
-- DRAGON_EQUIPMENT
-- Items slotted onto a dragon. Slot names: head, body, wings, claws, tail.
-- ---------------------------------------------------------------------------

CREATE TABLE public.dragon_equipment (
    id          UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    dragon_id   UUID    NOT NULL REFERENCES public.dragons(id) ON DELETE CASCADE,
    slot        TEXT    NOT NULL CHECK (slot IN ('head','body','wings','claws','tail')),
    item_name   TEXT    NOT NULL,
    -- Stat modifiers stored as JSONB so new stats don't require schema changes.
    -- Example: {"attack": 50, "defense": 30, "speed": 10}
    stats       JSONB   NOT NULL DEFAULT '{}',
    UNIQUE (dragon_id, slot)
);

ALTER TABLE public.dragon_equipment ENABLE ROW LEVEL SECURITY;
-- Join through dragons to verify ownership.
CREATE POLICY "dragon_equipment: owner via dragon" ON public.dragon_equipment
    USING (
        EXISTS (
            SELECT 1 FROM public.dragons d
            WHERE d.id = dragon_id AND d.player_id = auth.uid()
        )
    );


-- ---------------------------------------------------------------------------
-- MARCHES
-- Armies moving on the world map. status transitions:
--   marching → arrived (after arrive_at) → returning → returned
-- All combat and occupation logic is resolved server-side in Edge Functions
-- triggered when status becomes 'arrived'.
-- ---------------------------------------------------------------------------

CREATE TYPE march_status_enum AS ENUM ('marching', 'arrived', 'returning', 'returned', 'recalled');
CREATE TYPE march_type_enum   AS ENUM ('occupy', 'attack_npc', 'attack_player', 'reinforce', 'scout');

CREATE TABLE public.marches (
    id           UUID             PRIMARY KEY DEFAULT uuid_generate_v4(),
    player_id    UUID             NOT NULL REFERENCES public.players(id) ON DELETE CASCADE,
    dragon_id    UUID             REFERENCES public.dragons(id) ON DELETE SET NULL,
    march_type   march_type_enum  NOT NULL,
    status       march_status_enum NOT NULL DEFAULT 'marching',
    origin_x     INTEGER          NOT NULL,
    origin_y     INTEGER          NOT NULL,
    target_x     INTEGER          NOT NULL,
    target_y     INTEGER          NOT NULL,
    -- Army composition stored as JSONB: {"swordsmen": 100, "archers": 50}
    troops       JSONB            NOT NULL DEFAULT '{}',
    depart_at    TIMESTAMPTZ      NOT NULL DEFAULT NOW(),
    arrive_at    TIMESTAMPTZ      NOT NULL,
    return_at    TIMESTAMPTZ
);

ALTER TABLE public.marches ENABLE ROW LEVEL SECURITY;
CREATE POLICY "marches: owner only" ON public.marches
    USING (auth.uid() = player_id)
    WITH CHECK (auth.uid() = player_id);


-- ---------------------------------------------------------------------------
-- NPC_CAMPS
-- Static NPC strongholds seeded on the world map. Attacked by marches.
-- ---------------------------------------------------------------------------

CREATE TABLE public.npc_camps (
    id           UUID    PRIMARY KEY DEFAULT uuid_generate_v4(),
    x            INTEGER NOT NULL,
    y            INTEGER NOT NULL,
    camp_name    TEXT    NOT NULL,
    level        SMALLINT NOT NULL DEFAULT 1,
    -- Loot table: {"wood": 500, "food": 300, "dragon_egg_chance": 0.05}
    loot_table   JSONB   NOT NULL DEFAULT '{}',
    -- NULL = alive; timestamp = when it respawns
    respawn_at   TIMESTAMPTZ,
    UNIQUE (x, y)
);

ALTER TABLE public.npc_camps ENABLE ROW LEVEL SECURITY;
-- NPC camps are publicly readable (needed for map rendering).
CREATE POLICY "npc_camps: public read" ON public.npc_camps
    FOR SELECT USING (true);


-- ---------------------------------------------------------------------------
-- AUTO-CREATE PLAYER ROW ON FIRST SIGN-IN
-- Triggered when a new row appears in auth.users.
-- display_name defaults to the email prefix until the player sets one.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    INSERT INTO public.players (id, display_name)
    VALUES (
        NEW.id,
        SPLIT_PART(NEW.email, '@', 1)
    );
    INSERT INTO public.player_resources (player_id)
    VALUES (NEW.id);
    RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ---------------------------------------------------------------------------
-- ENABLE REALTIME on world_tiles (so Godot WebSocket client gets live updates)
-- ---------------------------------------------------------------------------

ALTER PUBLICATION supabase_realtime ADD TABLE public.world_tiles;
ALTER PUBLICATION supabase_realtime ADD TABLE public.marches;
