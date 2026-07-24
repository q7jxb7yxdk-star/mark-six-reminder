import type { DrawInfo, DrawSource, DrawStore } from "../models/draw";

/** Coordinates one official data refresh without exposing parser details to handlers. */
export class DrawUpdateService {
  /** Creates an update service with its source and persistence dependencies. */
  constructor(
    private readonly source: DrawSource,
    private readonly store: DrawStore,
  ) {}

  /** Fetches, validates and persists the latest upcoming draw. */
  async update(now = new Date()): Promise<DrawInfo> {
    const draw = await this.source.fetchCurrent(now);
    await this.store.saveCurrent(draw);
    return draw;
  }
}
