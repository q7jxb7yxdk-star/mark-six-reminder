import type { DrawSnapshot, DrawSource, DrawStore } from "../models/draw";

/** Coordinates one official data refresh without exposing parser details to handlers. */
export class DrawUpdateService {
  /** Creates an update service with its source and persistence dependencies. */
  constructor(
    private readonly source: DrawSource,
    private readonly store: DrawStore,
  ) {}

  /** Fetches, validates and persists all available draws plus the current snapshot. */
  async update(now = new Date()): Promise<DrawSnapshot> {
    const snapshot = await this.source.fetchSnapshot(now);
    await this.store.saveSnapshot(snapshot);
    return snapshot;
  }
}
