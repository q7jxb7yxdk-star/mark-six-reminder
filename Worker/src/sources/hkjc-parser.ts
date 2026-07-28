import type { DrawInfo, DrawSnapshot } from "../models/draw";

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

/** Parses an official HKJC GraphQL response into a validated multi-draw snapshot. */
export function parseHKJCResponse(payload: string, now = new Date()): DrawSnapshot {
  const response = decodePayload(payload);
  const upstreamError = response.errors?.map((error) => error.message).filter(Boolean).join(", ");

  if (upstreamError) {
    throw new HKJCParseError(`HKJC GraphQL error: ${upstreamError}`);
  }

  const draws = response.data?.lotteryDraws;
  if (!draws || draws.length === 0) {
    throw new HKJCParseError("HKJC response did not include lotteryDraws");
  }

  const availableDraws = draws
    .filter(hasRequiredFields)
    .map((draw) => normalizeDraw(draw, now))
    .sort((left, right) => Date.parse(left.drawDate) - Date.parse(right.drawDate));

  if (availableDraws.length === 0) {
    throw new HKJCParseError("HKJC response did not include any valid draws");
  }

  const current = selectNextDraw(availableDraws, now);
  return { current, draws: availableDraws };
}

/** Decodes JSON while converting implementation-specific syntax errors. */
function decodePayload(payload: string): HKJCResponse {
  try {
    return JSON.parse(payload) as HKJCResponse;
  } catch {
    throw new HKJCParseError("HKJC response was not valid JSON");
  }
}

/** Selects the earliest normalized undrawn draw that has not already passed, if available. */
function selectNextDraw(draws: DrawInfo[], now: Date): DrawInfo | null {
  return draws.find((draw) => {
    const timestamp = Date.parse(draw.drawDate);
    return draw.mainNumbers.length === 0 && timestamp >= now.valueOf();
  }) ?? null;
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
    estimatedFirstPrizeFund: parseOptionalNonNegativeInteger(
      draw.lotteryPool?.derivedFirstPrizeDiv,
    ),
    jackpot: parseOptionalNonNegativeInteger(draw.lotteryPool?.jackpot),
    status: draw.status ?? "Unknown",
    mainNumbers,
    specialNumber,
    updatedAt: now.toISOString(),
    sourceURL: OFFICIAL_MARK_SIX_URL,
  };
}

/** Parses optional whole-dollar values without allowing invalid money to discard draw results. */
function parseOptionalNonNegativeInteger(
  value: number | string | null | undefined,
): number | null {
  if (value == null) {
    return null;
  }

  if (typeof value === "number") {
    return Number.isSafeInteger(value) && value >= 0 ? value : null;
  }

  const trimmedValue = value.trim();
  const amountWithoutCurrency = trimmedValue.replace(/^(?:HK)?\$\s*/i, "");
  const isPlainInteger = /^\d+$/.test(amountWithoutCurrency);
  const isGroupedInteger = /^\d{1,3}(?:,\d{3})+$/.test(amountWithoutCurrency);
  if (!isPlainInteger && !isGroupedInteger) {
    return null;
  }

  const amount = Number(amountWithoutCurrency.replaceAll(",", ""));
  return Number.isSafeInteger(amount) && amount >= 0 ? amount : null;
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
