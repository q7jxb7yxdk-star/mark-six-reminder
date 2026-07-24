import { describe, expect, it } from "vitest";
import type { DrawInfo, DrawSnapshot, DrawSource, DrawStore } from "../src/models/draw";
import { DrawUpdateService } from "../src/services/draw-update-service";

const DRAW: DrawInfo = {
  id: "2026-076",
  drawNumber: "26/076",
  drawDate: "2026-07-16T21:30:00+08:00",
  salesCloseAt: "2026-07-16T21:15:00+08:00",
  estimatedFirstPrizeFund: 30_000_000,
  jackpot: 18_000_000,
  status: "StartSell",
  mainNumbers: [],
  specialNumber: null,
  updatedAt: "2026-07-15T12:00:00.000Z",
  sourceURL: "https://bet.hkjc.com/ch/marksix",
};

class StubSource implements DrawSource {
  /** Returns the controlled fixture used by this unit test. */
  async fetchSnapshot(): Promise<DrawSnapshot> {
    return { current: DRAW, draws: [DRAW] };
  }
}

class RecordingStore implements DrawStore {
  savedSnapshot: DrawSnapshot | null = null;

  /** Returns the draw most recently recorded by the test. */
  async getCurrent(): Promise<DrawInfo | null> {
    return this.savedSnapshot?.current ?? null;
  }

  /** Returns one draw from the recorded snapshot. */
  async getById(id: string): Promise<DrawInfo | null> {
    return this.savedSnapshot?.draws.find((draw) => draw.id === id) ?? null;
  }

  /** Records the supplied snapshot without external persistence. */
  async saveSnapshot(snapshot: DrawSnapshot): Promise<void> {
    this.savedSnapshot = snapshot;
  }
}

describe("DrawUpdateService", () => {
  it("persists the validated source result", async () => {
    const store = new RecordingStore();
    const service = new DrawUpdateService(new StubSource(), store);

    const result = await service.update();

    expect(result).toEqual({ current: DRAW, draws: [DRAW] });
    expect(store.savedSnapshot).toEqual(result);
  });
});
