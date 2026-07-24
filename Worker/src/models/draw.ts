/** A normalized Mark Six draw returned by the Jackpot Alert API. */
export interface DrawInfo {
  id: string;
  drawNumber: string;
  drawDate: string;
  salesCloseAt: string;
  estimatedFirstPrizeFund: number | null;
  jackpot: number | null;
  status: string;
  mainNumbers: number[];
  specialNumber: number | null;
  updatedAt: string;
  sourceURL: string;
}

/** One official refresh containing the current draw and all validated available draws. */
export interface DrawSnapshot {
  current: DrawInfo | null;
  draws: DrawInfo[];
}

/** Storage contract used by the update service. */
export interface DrawStore {
  /** Returns the most recently cached next draw, if one exists. */
  getCurrent(): Promise<DrawInfo | null>;

  /** Returns one cached historical or upcoming draw by its official identifier. */
  getById(id: string): Promise<DrawInfo | null>;

  /** Persists all validated draws before replacing the current public snapshot. */
  saveSnapshot(snapshot: DrawSnapshot): Promise<void>;
}

/** Source contract used to isolate the change-prone HKJC integration. */
export interface DrawSource {
  /** Fetches all available draws and identifies the next available Mark Six draw. */
  fetchSnapshot(now?: Date): Promise<DrawSnapshot>;
}
