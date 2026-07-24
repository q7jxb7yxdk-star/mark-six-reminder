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

/** Storage contract used by the update service. */
export interface DrawStore {
  /** Returns the most recently cached next draw, if one exists. */
  getCurrent(): Promise<DrawInfo | null>;

  /** Persists a validated draw as the current public snapshot. */
  saveCurrent(draw: DrawInfo): Promise<void>;
}

/** Source contract used to isolate the change-prone HKJC integration. */
export interface DrawSource {
  /** Fetches and normalizes the next available Mark Six draw. */
  fetchCurrent(now?: Date): Promise<DrawInfo>;
}
