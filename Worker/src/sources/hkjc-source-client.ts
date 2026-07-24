import type { DrawSnapshot, DrawSource } from "../models/draw";
import { HKJCParseError, parseHKJCResponse } from "./hkjc-parser";

const MAX_RESPONSE_BYTES = 256 * 1024;

const MARK_SIX_QUERY = `
  fragment lotteryDrawsFragment on LotteryDraw {
    id
    year
    no
    openDate
    closeDate
    drawDate
    status
    snowballCode
    snowballName_en
    snowballName_ch
    lotteryPool {
      sell
      status
      totalInvestment
      jackpot
      unitBet
      estimatedPrize
      derivedFirstPrizeDiv
      lotteryPrizes {
        type
        winningUnit
        dividend
      }
    }
    drawResult {
      drawnNo
      xDrawnNo
    }
  }
  query marksixDraw {
    timeOffset {
      m6
      ts
    }
    lotteryDraws {
      ...lotteryDrawsFragment
    }
  }
`;

/** Fetches Mark Six data from the endpoint used by the official HKJC page. */
export class HKJCSourceClient implements DrawSource {
  /** Creates a source client for the configurable official endpoint. */
  constructor(private readonly endpoint: string) {}

  /** Downloads a bounded GraphQL response and converts it into a stable model. */
  async fetchSnapshot(now = new Date()): Promise<DrawSnapshot> {
    const response = await fetch(this.endpoint, {
      method: "POST",
      headers: {
        accept: "application/json",
        "content-type": "application/json",
        origin: "https://bet.hkjc.com",
        referer: "https://bet.hkjc.com/",
      },
      body: JSON.stringify({
        operationName: "marksixDraw",
        variables: {},
        query: MARK_SIX_QUERY,
      }),
      signal: AbortSignal.timeout(8_000),
    });

    if (!response.ok) {
      throw new HKJCParseError(`HKJC request failed with HTTP ${response.status}`);
    }

    const payload = await readBoundedText(response, MAX_RESPONSE_BYTES);
    return parseHKJCResponse(payload, now);
  }
}

/** Reads an upstream response while enforcing a fixed memory ceiling. */
async function readBoundedText(response: Response, maximumBytes: number): Promise<string> {
  const declaredLength = Number(response.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new HKJCParseError("HKJC response exceeded the allowed size");
  }

  if (!response.body) {
    throw new HKJCParseError("HKJC response did not include a body");
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let receivedBytes = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }

    receivedBytes += value.byteLength;
    if (receivedBytes > maximumBytes) {
      await reader.cancel();
      throw new HKJCParseError("HKJC response exceeded the allowed size");
    }

    chunks.push(value);
  }

  const body = new Uint8Array(receivedBytes);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }

  return new TextDecoder().decode(body);
}
