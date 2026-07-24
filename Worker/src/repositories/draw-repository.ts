import type { DrawInfo, DrawStore } from "../models/draw";

const CURRENT_DRAW_CACHE_KEY = "draw:current";

interface DrawRow {
  id: string;
  draw_number: string;
  draw_date: string;
  sales_close_at: string;
  estimated_first_prize_fund: number | null;
  jackpot: number | null;
  status: string;
  main_numbers: string;
  special_number: number | null;
  updated_at: string;
  source_url: string;
}

/** Persists draw snapshots in D1 and serves the hot copy from KV. */
export class DrawRepository implements DrawStore {
  /** Creates a repository backed by the configured Worker bindings. */
  constructor(
    private readonly database: D1Database,
    private readonly cache: KVNamespace,
  ) {}

  /** Reads KV first and falls back to the latest D1 record. */
  async getCurrent(): Promise<DrawInfo | null> {
    const cached = await this.cache.get<DrawInfo>(CURRENT_DRAW_CACHE_KEY, "json");
    if (cached) {
      return cached;
    }

    const row = await this.database
      .prepare("SELECT * FROM draws ORDER BY draw_date DESC LIMIT 1")
      .first<DrawRow>();

    if (!row) {
      return null;
    }

    const draw = mapRow(row);
    await this.cache.put(CURRENT_DRAW_CACHE_KEY, JSON.stringify(draw));
    return draw;
  }

  /** Upserts the durable record before replacing the current KV snapshot. */
  async saveCurrent(draw: DrawInfo): Promise<void> {
    await this.database
      .prepare(
        `INSERT INTO draws (
          id, draw_number, draw_date, sales_close_at,
          estimated_first_prize_fund, jackpot, status,
          main_numbers, special_number, updated_at, source_url
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          draw_number = excluded.draw_number,
          draw_date = excluded.draw_date,
          sales_close_at = excluded.sales_close_at,
          estimated_first_prize_fund = excluded.estimated_first_prize_fund,
          jackpot = excluded.jackpot,
          status = excluded.status,
          main_numbers = excluded.main_numbers,
          special_number = excluded.special_number,
          updated_at = excluded.updated_at,
          source_url = excluded.source_url`,
      )
      .bind(
        draw.id,
        draw.drawNumber,
        draw.drawDate,
        draw.salesCloseAt,
        draw.estimatedFirstPrizeFund,
        draw.jackpot,
        draw.status,
        JSON.stringify(draw.mainNumbers),
        draw.specialNumber,
        draw.updatedAt,
        draw.sourceURL,
      )
      .run();

    await this.cache.put(CURRENT_DRAW_CACHE_KEY, JSON.stringify(draw));
  }
}

/** Converts the D1 representation back into the public API model. */
function mapRow(row: DrawRow): DrawInfo {
  const mainNumbers = JSON.parse(row.main_numbers) as unknown;
  if (!Array.isArray(mainNumbers) || !mainNumbers.every((number) => typeof number === "number")) {
    throw new Error("Stored draw contains invalid main_numbers");
  }

  return {
    id: row.id,
    drawNumber: row.draw_number,
    drawDate: row.draw_date,
    salesCloseAt: row.sales_close_at,
    estimatedFirstPrizeFund: row.estimated_first_prize_fund,
    jackpot: row.jackpot,
    status: row.status,
    mainNumbers,
    specialNumber: row.special_number,
    updatedAt: row.updated_at,
    sourceURL: row.source_url,
  };
}
