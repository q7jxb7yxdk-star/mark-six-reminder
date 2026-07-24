import { describe, expect, it } from "vitest";
import { HKJCParseError, parseHKJCResponse } from "../src/sources/hkjc-parser";

const NOW = new Date("2026-07-15T12:00:00.000Z");

/** Creates a representative response using the schema published by HKJC's current frontend. */
function makeFixture(): string {
  return JSON.stringify({
    data: {
      lotteryDraws: [
        {
          id: "202675N",
          year: "2026",
          no: 75,
          closeDate: "2026-07-14T21:15:00+08:00",
          drawDate: "2026-07-14+08:00",
          status: "Result",
          lotteryPool: { jackpot: "12000000", derivedFirstPrizeDiv: "20000000" },
          drawResult: { drawnNo: [3, 8, 17, 24, 36, 45], xDrawnNo: 9 },
        },
        {
          id: "202676N",
          year: "2026",
          no: 76,
          closeDate: "2026-07-16T21:15:00+08:00",
          drawDate: "2026-07-16+08:00",
          status: "Defined",
          lotteryPool: { jackpot: "18000000", derivedFirstPrizeDiv: "30000000" },
          drawResult: { drawnNo: [], xDrawnNo: 10 },
        },
      ],
    },
  });
}

describe("parseHKJCResponse", () => {
  it("selects and normalizes the next undrawn draw", () => {
    const draw = parseHKJCResponse(makeFixture(), NOW);

    expect(draw).toMatchObject({
      id: "202676N",
      drawNumber: "26/076",
      drawDate: "2026-07-16T21:30:00+08:00",
      status: "Defined",
      estimatedFirstPrizeFund: 30_000_000,
      jackpot: 18_000_000,
      mainNumbers: [],
      specialNumber: null,
    });
  });

  it("rejects GraphQL errors instead of overwriting the last good cache", () => {
    const payload = JSON.stringify({ errors: [{ message: "WHITELIST_ERROR" }], data: null });

    expect(() => parseHKJCResponse(payload, NOW)).toThrow(HKJCParseError);
  });

  it("rejects a response with no upcoming draw", () => {
    const payload = JSON.stringify({ data: { lotteryDraws: [] } });

    expect(() => parseHKJCResponse(payload, NOW)).toThrow("did not include lotteryDraws");
  });

  it("rejects non-numeric monetary strings", () => {
    const fixture = JSON.parse(makeFixture()) as {
      data: { lotteryDraws: Array<{ lotteryPool: { derivedFirstPrizeDiv: string } }> };
    };
    fixture.data.lotteryDraws[1]!.lotteryPool.derivedFirstPrizeDiv = "$30,000,000";

    expect(() => parseHKJCResponse(JSON.stringify(fixture), NOW)).toThrow(
      "invalid monetary value",
    );
  });
});
