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
    const snapshot = parseHKJCResponse(makeFixture(), NOW);

    expect(snapshot.current).toMatchObject({
      id: "202676N",
      drawNumber: "26/076",
      drawDate: "2026-07-16T21:30:00+08:00",
      status: "Defined",
      estimatedFirstPrizeFund: 30_000_000,
      jackpot: 18_000_000,
      mainNumbers: [],
      specialNumber: null,
    });
    expect(snapshot.draws).toHaveLength(2);
    expect(snapshot.draws[0]).toMatchObject({
      id: "202675N",
      mainNumbers: [3, 8, 17, 24, 36, 45],
      specialNumber: 9,
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

  it("keeps published results when the next draw is not available yet", () => {
    const fixture = JSON.parse(makeFixture()) as {
      data: { lotteryDraws: unknown[] };
    };
    fixture.data.lotteryDraws = fixture.data.lotteryDraws.slice(0, 1);

    const snapshot = parseHKJCResponse(JSON.stringify(fixture), NOW);

    expect(snapshot.current).toBeNull();
    expect(snapshot.draws).toHaveLength(1);
    expect(snapshot.draws[0]?.mainNumbers).toEqual([3, 8, 17, 24, 36, 45]);
  });

  it("accepts currency symbols and grouped monetary strings", () => {
    const fixture = JSON.parse(makeFixture()) as {
      data: {
        lotteryDraws: Array<{
          lotteryPool: { jackpot: string; derivedFirstPrizeDiv: string };
        }>;
      };
    };
    fixture.data.lotteryDraws[1]!.lotteryPool.jackpot = "HK$ 18,000,000";
    fixture.data.lotteryDraws[1]!.lotteryPool.derivedFirstPrizeDiv = "$30,000,000";

    const snapshot = parseHKJCResponse(JSON.stringify(fixture), NOW);

    expect(snapshot.current?.jackpot).toBe(18_000_000);
    expect(snapshot.current?.estimatedFirstPrizeFund).toBe(30_000_000);
  });

  it("ignores unavailable or malformed optional money without discarding results", () => {
    const fixture = JSON.parse(makeFixture()) as {
      data: {
        lotteryDraws: Array<{
          lotteryPool: { jackpot: number | string; derivedFirstPrizeDiv: string };
        }>;
      };
    };
    fixture.data.lotteryDraws[0]!.lotteryPool.jackpot = "-";
    fixture.data.lotteryDraws[1]!.lotteryPool.jackpot = -1;
    fixture.data.lotteryDraws[1]!.lotteryPool.derivedFirstPrizeDiv = "not available";

    const snapshot = parseHKJCResponse(JSON.stringify(fixture), NOW);

    expect(snapshot.draws[0]).toMatchObject({
      jackpot: null,
      mainNumbers: [3, 8, 17, 24, 36, 45],
      specialNumber: 9,
    });
    expect(snapshot.current).toMatchObject({
      jackpot: null,
      estimatedFirstPrizeFund: null,
    });
  });
});
