import { mkdirSync } from "node:fs";
import { dirname } from "node:path";
import Database from "better-sqlite3";

const GLOBAL_WAHS_KEY = "global_wahs";

export function openCounterDatabase(databasePath, initialWahs = 0) {
  if (databasePath !== ":memory:") {
    mkdirSync(dirname(databasePath), { recursive: true });
  }

  const database = new Database(databasePath);
  database.exec(`
    PRAGMA journal_mode = WAL;
    PRAGMA synchronous = NORMAL;
    PRAGMA busy_timeout = 5000;

    CREATE TABLE IF NOT EXISTS counters (
      key TEXT PRIMARY KEY,
      value INTEGER NOT NULL CHECK (value >= 0),
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) STRICT;

    CREATE TABLE IF NOT EXISTS players (
      id TEXT PRIMARY KEY,
      public_code TEXT NOT NULL UNIQUE,
      token_hash TEXT NOT NULL UNIQUE,
      score INTEGER NOT NULL DEFAULT 0 CHECK (score >= 0),
      has_migrated INTEGER NOT NULL DEFAULT 0 CHECK (has_migrated IN (0, 1)),
      earth_enabled INTEGER NOT NULL DEFAULT 0 CHECK (earth_enabled IN (0, 1)),
      location_cell TEXT,
      location_lat REAL,
      location_lon REAL,
      location_updated_at TEXT,
      last_wah_at INTEGER,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    ) STRICT;

    CREATE INDEX IF NOT EXISTS players_score_index
      ON players(score DESC, public_code ASC);
  `);

  // SQLite's CREATE TABLE IF NOT EXISTS does not add columns to installations
  // created by older App Store builds. Keep this migration additive so the
  // existing counter and leaderboard data remain intact during deployment.
  const playerColumns = new Set(
    database.prepare("PRAGMA table_info(players)").all().map((column) => column.name)
  );
  const additions = [
    ["earth_enabled", "INTEGER NOT NULL DEFAULT 0 CHECK (earth_enabled IN (0, 1))"],
    ["location_cell", "TEXT"],
    ["location_lat", "REAL"],
    ["location_lon", "REAL"],
    ["location_updated_at", "TEXT"],
    ["last_wah_at", "INTEGER"]
  ];
  for (const [name, definition] of additions) {
    if (!playerColumns.has(name)) {
      database.exec(`ALTER TABLE players ADD COLUMN ${name} ${definition}`);
    }
  }
  database.exec(`
    CREATE INDEX IF NOT EXISTS players_earth_location_index
      ON players(earth_enabled, location_lat, location_lon);
    CREATE INDEX IF NOT EXISTS players_earth_activity_index
      ON players(earth_enabled, last_wah_at);
  `);

  database.prepare(`
    INSERT OR IGNORE INTO counters (key, value)
    VALUES (?, ?)
  `).run(GLOBAL_WAHS_KEY, initialWahs);

  const readWahs = database.prepare(
    "SELECT value FROM counters WHERE key = ?"
  );
  const addWahs = database.prepare(`
    UPDATE counters
    SET value = value + ?, updated_at = CURRENT_TIMESTAMP
    WHERE key = ?
    RETURNING value
  `);
  const createPlayer = database.prepare(`
    INSERT INTO players (id, public_code, token_hash)
    VALUES (@id, @publicCode, @tokenHash)
  `);
  const readPlayerByToken = database.prepare(`
    SELECT id, public_code AS publicCode, score, has_migrated AS hasMigrated,
      earth_enabled AS earthEnabled, location_cell AS locationCell,
      location_lat AS locationLat, location_lon AS locationLon,
      last_wah_at AS lastWahAt
    FROM players
    WHERE token_hash = ?
  `);
  const readPlayerByID = database.prepare(`
    SELECT id, public_code AS publicCode, score, has_migrated AS hasMigrated,
      earth_enabled AS earthEnabled, location_cell AS locationCell,
      location_lat AS locationLat, location_lon AS locationLon,
      last_wah_at AS lastWahAt
    FROM players
    WHERE id = ?
  `);
  const deletePlayer = database.prepare("DELETE FROM players WHERE id = ?");

  const migratePlayer = database.transaction((playerID, personal, pendingGlobal) => {
    const player = readPlayerByID.get(playerID);
    if (!player) {
      return undefined;
    }
    if (player.hasMigrated === 1) {
      return { ...player, didMigrate: false };
    }

    addWahs.run(pendingGlobal, GLOBAL_WAHS_KEY);
    database.prepare(`
      UPDATE players
      SET score = ?, has_migrated = 1, updated_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(personal, playerID);
    return { ...readPlayerByID.get(playerID), didMigrate: true };
  });

  const submitScore = database.transaction((playerID, targetScore, timestamp) => {
    const player = readPlayerByID.get(playerID);
    if (!player || player.hasMigrated !== 1) {
      return undefined;
    }

    const delta = Math.max(targetScore - player.score, 0);
    if (delta > 0) {
      database.prepare(`
        UPDATE players
        SET score = ?, last_wah_at = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(targetScore, timestamp, playerID);
      addWahs.run(delta, GLOBAL_WAHS_KEY);
    }
    return {
      score: Math.max(player.score, targetScore),
      delta,
      lastWahAt: delta > 0 ? timestamp : player.lastWahAt
    };
  });

  const enableEarth = database.prepare(`
    UPDATE players
    SET earth_enabled = 1,
      location_cell = @cell,
      location_lat = @latitude,
      location_lon = @longitude,
      location_updated_at = CURRENT_TIMESTAMP,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = @playerID
  `);
  const disableEarth = database.prepare(`
    UPDATE players
    SET earth_enabled = 0,
      location_cell = NULL,
      location_lat = NULL,
      location_lon = NULL,
      location_updated_at = NULL,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = ?
  `);
  const readEarthPlayers = database.prepare(`
    SELECT id, public_code AS publicCode, score,
      location_cell AS locationCell,
      location_lat AS locationLat,
      location_lon AS locationLon,
      last_wah_at AS lastWahAt
    FROM players
    WHERE earth_enabled = 1
      AND has_migrated = 1
      AND location_cell IS NOT NULL
      AND location_lat IS NOT NULL
      AND location_lon IS NOT NULL
  `);

  const rankedPlayersSQL = `
    WITH ranked AS (
      SELECT
        id,
        public_code AS publicCode,
        score,
        RANK() OVER (ORDER BY score DESC) AS rank
      FROM players
      WHERE has_migrated = 1
    )
  `;
  const readTopPlayers = database.prepare(`
    ${rankedPlayersSQL}
    SELECT id, publicCode, score, rank
    FROM ranked
    ORDER BY rank ASC, publicCode ASC
    LIMIT ?
  `);
  const readRankedPlayer = database.prepare(`
    ${rankedPlayersSQL}
    SELECT id, publicCode, score, rank
    FROM ranked
    WHERE id = ?
  `);
  const countRankedPlayers = database.prepare(`
    SELECT COUNT(*) AS count FROM players WHERE has_migrated = 1
  `);

  return {
    getWahs() {
      return Number(readWahs.get(GLOBAL_WAHS_KEY).value);
    },

    incrementWahs(count) {
      return Number(addWahs.get(count, GLOBAL_WAHS_KEY).value);
    },

    createPlayer(player) {
      createPlayer.run(player);
      return readPlayerByID.get(player.id);
    },

    getPlayerByTokenHash(tokenHash) {
      return readPlayerByToken.get(tokenHash);
    },

    migratePlayer(playerID, personal, pendingGlobal) {
      return migratePlayer(playerID, personal, pendingGlobal);
    },

    submitScore(playerID, targetScore, timestamp = Date.now()) {
      return submitScore(playerID, targetScore, timestamp);
    },

    setEarthLocation(playerID, location) {
      enableEarth.run({ playerID, ...location });
      return readPlayerByID.get(playerID);
    },

    disableEarth(playerID) {
      disableEarth.run(playerID);
      return readPlayerByID.get(playerID);
    },

    earthPlayers() {
      return readEarthPlayers.all();
    },

    leaderboard(playerID, limit) {
      return {
        entries: readTopPlayers.all(limit),
        me: readRankedPlayer.get(playerID),
        totalPlayers: Number(countRankedPlayers.get().count)
      };
    },

    deletePlayer(playerID) {
      return deletePlayer.run(playerID).changes === 1;
    },

    close() {
      database.close();
    }
  };
}
