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

  return {
    getWahs() {
      return Number(readWahs.get(GLOBAL_WAHS_KEY).value);
    },

    incrementWahs(count) {
      return Number(addWahs.get(count, GLOBAL_WAHS_KEY).value);
    },

    close() {
      database.close();
    }
  };
}
