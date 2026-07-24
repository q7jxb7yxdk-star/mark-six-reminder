import type { DrawInfo } from "../models/draw";

const OFFICIAL_MARK_SIX_URL = "https://bet.hkjc.com/ch/marksix";

interface GraphQLErrorPayload {
  message?: string;
}

interface HKJCResponse {
  data?: {
    lotteryDraws?: HKJCDraw[] | null;
  } | null;
  errors?: GraphQLErrorPayload[];
}

interface HKJCDraw {
  id?: string | null;
  year?: string | null;
  no?: number | null;
  closeDate?: string | null;
  drawDate?: string | null;
  status?: string | null;
  lotteryPool?: {
    jackpot?: number | string | null;
    derivedFirstPrizeDiv?: number | string | null;
  } | null;
  drawResult?: {
    drawnNo?: number[] | null;
    xDrawnNo?: number | null;
  } | null;
}

/** Raised when the official response is unavailable or violates the expected schema. */
export class HKJCParseError extends Error {
  /** Creates a parser error with a stable class name for structured logging. */
  constructor(message: string) {
    super(message);
    this.name = "HKJCParseError";
  }
}

/** Parses an official HKJC GraphQL response into the app's stable draw schema. */
export function parseHKJCResponse(payload: string, now = new Date()): DrawInfo {
  const response = decodePayload(payload);
  const upstreamError = response.errors?.map((error) => error.message).filter(Boolean).join(", ");

  if (upstreamError) {
    throw new HKJCParseError(`HKJC GraphQL error: ${upstreamError}`);
  }

  const draws = response.data?.lotteryDraws;
  if (!draws || draws.length === 0) {
    throw new HKJCParseError("HKJC response did not include lotteryDraws");
  }

  const candidate = selectNextDraw(draws, now);
  return normalizeDraw(candidate, now);
}

/** Decodes JSON while converting implementation-specific syntax errors. */
function decodePayload(payload: string): HKJCResponse {
  try {
    return JSON.parse(payload) as HKJCResponse;
  } catch {
    throw new HKJCParseError("HKJC response was not valid JSON");
  }
}

/** Selects the earliest undrawn draw that has not already passed. */
function selectNextDraw(draws: HKJCDraw[], now: Date): HKJCDraw {
  const validDraws = draws
    .filter(hasRequiredFields)
    .map((draw) => ({ draw, date: parseDrawDate(draw.drawDate as string) }))
    .filter((candidate): candidate is { draw: HKJCDraw; date: Date } => candidate.date !== null)
    .sort((left, right) => left.date.valueOf() - right.date.valueOf());

  const upcoming = validDraws.find(({ draw, date }) => {
    const hasResult = (draw.drawResult?.drawnNo?.length ?? 0) > 0;
    return !hasResult && date.valueOf() >= now.valueOf();
  });

  if (!upcoming) {
    throw new HKJCParseError("HKJC response did not include an upcoming draw");
  }

  return upcoming.draw;
}

/** Checks the minimum fields required to produce a stable public response. */
function hasRequiredFields(draw: HKJCDraw): boolean {
  return Boolean(draw.id && draw.year && draw.no != null && draw.drawDate && draw.closeDate);
}

/** Converts a validated upstream draw into the public API model. */
function normalizeDraw(draw: HKJCDraw, now: Date): DrawInfo {
  const year = draw.year as string;
  const drawSequence = String(draw.no).padStart(3, "0");
  const mainNumbers = draw.drawResult?.drawnNo ?? [];
  const specialNumber = mainNumbers.length === 6
    ? draw.drawResult?.xDrawnNo ?? null
    : null;

  validateNumbers(mainNumbers, specialNumber);

  return {
    id: draw.id as string,
    drawNumber: `${year.slice(-2)}/${drawSequence}`,
    drawDate: normalizeDrawDate(draw.drawDate as string),
    salesCloseAt: draw.closeDate as string,
    estimatedFirstPrizeFund: toNonNegativeInteger(draw.lotteryPool?.derivedFirstPrizeDiv),
    jackpot: toNonNegativeInteger(draw.lotteryPool?.jackpot),
    status: draw.status ?? "Unknown",
    mainNumbers,
    specialNumber,
    updatedAt: now.toISOString(),
    sourceURL: OFFICIAL_MARK_SIX_URL,
  };
}

/** Normalizes optional monetary values while rejecting negative or invalid data. */
function toNonNegativeInteger(value: number | string | null | undefined): number | null {
  if (value == null) {
    return null;
  }

  const normalizedValue = typeof value === "string"
    ? parseIntegerString(value)
    : value;
  if (!Number.isSafeInteger(normalizedValue) || normalizedValue < 0) {
    throw new HKJCParseError("HKJC response included an invalid monetary value");
  }

  return normalizedValue;
}

/** Parses the digits-only monetary strings returned by marksixDraw. */
function parseIntegerString(value: string): number {
  const trimmedValue = value.trim();
  if (!/^\d+$/.test(trimmedValue)) {
    return Number.NaN;
  }
  return Number(trimmedValue);
}

/** Converts an official draw date into the app's ISO timestamp representation. */
function normalizeDrawDate(value: string): string {
  if (value.includes("T")) {
    const timestamp = new Date(value);
    if (!Number.isNaN(timestamp.valueOf())) {
      return value;
    }
  }

  const dateMatch = /^(\d{4}-\d{2}-\d{2})(?:[+-]\d{2}:\d{2})?$/.exec(value);
  if (!dateMatch?.[1]) {
    throw new HKJCParseError("HKJC response included an invalid drawDate");
  }

  const normalizedValue = `${dateMatch[1]}T21:30:00+08:00`;
  if (Number.isNaN(new Date(normalizedValue).valueOf())) {
    throw new HKJCParseError("HKJC response included an invalid drawDate");
  }
  return normalizedValue;
}

/** Parses a draw timestamp for chronological selection without leaking parser errors. */
function parseDrawDate(value: string): Date | null {
  try {
    return new Date(normalizeDrawDate(value));
  } catch {
    return null;
  }
}

/** Validates any published result numbers without requiring results for future draws. */
function validateNumbers(mainNumbers: number[], specialNumber: number | null): void {
  if (mainNumbers.length === 0 && specialNumber == null) {
    return;
  }

  const allNumbers = specialNumber == null ? mainNumbers : [...mainNumbers, specialNumber];
  const uniqueNumbers = new Set(allNumbers);
  const allInRange = allNumbers.every((number) => Number.isInteger(number) && number >= 1 && number <= 49);

  if (mainNumbers.length !== 6 || specialNumber == null || uniqueNumbers.size !== 7 || !allInRange) {
    throw new HKJCParseError("HKJC response included an invalid draw result");
  }
}
