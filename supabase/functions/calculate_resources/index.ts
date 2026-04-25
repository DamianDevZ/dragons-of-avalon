// calculate_resources — Supabase Edge Function (Deno / TypeScript)
//
// Called by the Godot client whenever it needs accurate resource totals.
// Implements delta-time math server-side so the client clock is never trusted.
//
// Flow:
//   1. Read player_resources row (last saved amounts + last_calculated_at)
//   2. Query all city_buildings and tile_buildings to sum production rates
//   3. production = base_rate × building_level × tile_bonus (if applicable)
//   4. elapsed = NOW() - last_calculated_at  (in seconds)
//   5. current = saved + (production_per_second × elapsed)
//   6. Write the new snapshot back to player_resources
//   7. Return the new totals to the client
//
// Deploy: supabase functions deploy calculate_resources

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Base production per second per building level.
// These are game-design constants — tune as needed.
const BASE_PRODUCTION: Record<string, Record<string, number>> = {
  lumber_mill: { wood: 0.5 },  // 0.5 wood/sec at level 1
  farm:        { food: 0.6 },
  quarry:      { stone: 0.4 },
  gold_mine:   { gold: 0.2 },
};

// Bonus multiplier when a tile_building's type matches the tile type.
// e.g. a lumber_mill on a forest tile gets +50% output.
const TILE_MATCH_BONUS: Record<string, string> = {
  lumber_mill: "forest",
  farm:        "field",
  quarry:      "mountain",
  gold_mine:   "mountain",
};
const TILE_BONUS_MULTIPLIER = 1.5;

Deno.serve(async (req: Request) => {
  // Only POST is accepted.
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Initialise a Supabase client that inherits the caller's auth context.
  // SUPABASE_URL and SUPABASE_ANON_KEY are injected automatically by the runtime.
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: {
        headers: { Authorization: req.headers.get("Authorization") ?? "" },
      },
    }
  );

  // Identify caller from the JWT.
  const { data: { user }, error: authError } = await supabase.auth.getUser();
  if (authError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }
  const playerId = user.id;

  // ── 1. Load the current saved snapshot ──────────────────────────────────
  const { data: resRow, error: resErr } = await supabase
    .from("player_resources")
    .select("wood, food, stone, gold, last_calculated_at")
    .eq("player_id", playerId)
    .single();

  if (resErr || !resRow) {
    return json({ error: "Could not load resources" }, 500);
  }

  const now       = new Date();
  const lastCalc  = new Date(resRow.last_calculated_at);
  const elapsed   = Math.max(0, (now.getTime() - lastCalc.getTime()) / 1000); // seconds

  // ── 2. Sum production rates from city buildings ──────────────────────────
  const { data: cityBuildings } = await supabase
    .from("city_buildings")
    .select("building_type, level, upgrade_complete_at")
    .eq("player_id", playerId);

  // ── 3. Sum production rates from tile buildings (with tile-type bonus) ───
  // Join tile_buildings with world_tiles to check for type matches.
  const { data: tileBuildings } = await supabase
    .from("tile_buildings")
    .select("building_type, level, tile_x, tile_y, world_tiles(tile_type)")
    .eq("player_id", playerId);

  const rates = { wood: 0, food: 0, stone: 0, gold: 0 };

  // City buildings — no tile bonus possible here.
  for (const b of (cityBuildings ?? [])) {
    const prod = BASE_PRODUCTION[b.building_type];
    if (!prod) continue;
    for (const [resource, baseRate] of Object.entries(prod)) {
      rates[resource as keyof typeof rates] += baseRate * b.level;
    }
  }

  // Tile buildings — apply bonus when type matches.
  for (const b of (tileBuildings ?? [])) {
    const prod = BASE_PRODUCTION[b.building_type];
    if (!prod) continue;
    const tileType    = (b as any).world_tiles?.tile_type ?? "";
    const matchesTile = TILE_MATCH_BONUS[b.building_type] === tileType;
    const multiplier  = matchesTile ? TILE_BONUS_MULTIPLIER : 1.0;
    for (const [resource, baseRate] of Object.entries(prod)) {
      rates[resource as keyof typeof rates] += baseRate * b.level * multiplier;
    }
  }

  // ── 4. Project forward ───────────────────────────────────────────────────
  const updated = {
    wood:  resRow.wood  + rates.wood  * elapsed,
    food:  resRow.food  + rates.food  * elapsed,
    stone: resRow.stone + rates.stone * elapsed,
    gold:  resRow.gold  + rates.gold  * elapsed,
    last_calculated_at: now.toISOString(),
  };

  // ── 5. Persist the new snapshot ──────────────────────────────────────────
  const { error: updateErr } = await supabase
    .from("player_resources")
    .update(updated)
    .eq("player_id", playerId);

  if (updateErr) {
    return json({ error: "Failed to save resources" }, 500);
  }

  // ── 6. Return totals + production rates (rates used by Godot for live UI) ─
  return json({
    wood:  updated.wood,
    food:  updated.food,
    stone: updated.stone,
    gold:  updated.gold,
    rates: rates,          // wood_per_sec, food_per_sec etc. for client-side extrapolation
    last_calculated_at: updated.last_calculated_at,
  });
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
