const HONG_KONG_DATE_FORMATTER = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Asia/Hong_Kong",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** Returns a stable calendar date key evaluated in the Hong Kong time zone. */
export function hongKongDateKey(date: Date): string {
  const parts = HONG_KONG_DATE_FORMATTER.formatToParts(date);
  const year = partValue(parts, "year");
  const month = partValue(parts, "month");
  const day = partValue(parts, "day");
  return `${year}-${month}-${day}`;
}

/** Reports whether an ISO draw timestamp falls on today's Hong Kong calendar date. */
export function isHongKongDrawDay(drawDate: string, now: Date): boolean {
  const parsedDrawDate = new Date(drawDate);
  if (Number.isNaN(parsedDrawDate.getTime())) {
    throw new Error("Draw contains an invalid drawDate");
  }

  return hongKongDateKey(parsedDrawDate) === hongKongDateKey(now);
}

/** Extracts a required date component from Intl output. */
function partValue(parts: Intl.DateTimeFormatPart[], type: Intl.DateTimeFormatPartTypes): string {
  const value = parts.find((part) => part.type === type)?.value;
  if (!value) {
    throw new Error(`Unable to format Hong Kong date component: ${type}`);
  }
  return value;
}
