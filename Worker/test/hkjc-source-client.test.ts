import { afterEach, describe, expect, it, vi } from "vitest";
import { HKJCSourceClient } from "../src/sources/hkjc-source-client";

const NOW = new Date("2026-07-24T04:00:00.000Z");

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("HKJCSourceClient", () => {
  it("uses the publicly accessible marksixDraw operation", async () => {
    const fetchMock = vi.fn<typeof fetch>(async () => new Response(JSON.stringify({
      data: {
        lotteryDraws: [
          {
            id: "202680N",
            year: "2026",
            no: 80,
            closeDate: "2026-07-25T21:15:00+08:00",
            drawDate: "2026-07-25+08:00",
            status: "Defined",
            lotteryPool: {
              jackpot: "8000000",
              derivedFirstPrizeDiv: "13000000",
            },
            drawResult: { drawnNo: [], xDrawnNo: 10 },
          },
        ],
      },
    })));
    vi.stubGlobal("fetch", fetchMock);

    const client = new HKJCSourceClient("https://info.cld.hkjc.com/graphql/base/");
    const draw = await client.fetchCurrent(NOW);

    const request = fetchMock.mock.calls[0];
    const requestBody = JSON.parse(String(request?.[1]?.body)) as {
      operationName?: string;
      variables?: unknown;
      query?: string;
    };
    expect(requestBody.operationName).toBe("marksixDraw");
    expect(requestBody.variables).toEqual({});
    expect(requestBody.query).toContain("fragment lotteryDrawsFragment");
    expect(requestBody.query).toContain("timeOffset");
    expect(draw).toMatchObject({
      id: "202680N",
      drawNumber: "26/080",
      estimatedFirstPrizeFund: 13_000_000,
      specialNumber: null,
    });
  });
});
