import { APIRequestError, routeRequest } from "./api/router";
import { DrawRepository } from "./repositories/draw-repository";
import { NotificationRepository } from "./repositories/notification-repository";
import { APNsClient, type APNsConfiguration } from "./services/apns-client";
import { DrawUpdateService } from "./services/draw-update-service";
import { NotificationService } from "./services/notification-service";
import { HKJCSourceClient } from "./sources/hkjc-source-client";

export default {
  /** Serves cached, validated draw data to the iOS app. */
  async fetch(request: Request, env: Env): Promise<Response> {
    const repository = new DrawRepository(env.DB, env.DRAW_CACHE);
    const notificationRepository = new NotificationRepository(env.DB);

    try {
      return await routeRequest(request, repository, notificationRepository);
    } catch (error) {
      if (error instanceof APIRequestError) {
        return new Response(
          JSON.stringify({ error: { code: error.code, message: error.message } }),
          {
            status: error.status,
            headers: { "content-type": "application/json; charset=utf-8" },
          },
        );
      }
      logError("api_request_failed", error);
      return new Response(
        JSON.stringify({ error: { code: "INTERNAL_ERROR", message: "Unexpected server error" } }),
        {
          status: 500,
          headers: { "content-type": "application/json; charset=utf-8" },
        },
      );
    }
  },

  /** Refreshes the next draw from HKJC on the configured UTC schedule. */
  async scheduled(_controller: ScheduledController, env: Env, _ctx: ExecutionContext): Promise<void> {
    const repository = new DrawRepository(env.DB, env.DRAW_CACHE);
    const source = new HKJCSourceClient(env.HKJC_GRAPHQL_URL);
    const service = new DrawUpdateService(source, repository);
    const notificationRepository = new NotificationRepository(env.DB);

    try {
      const draw = await service.update();
      console.log(JSON.stringify({ event: "draw_updated", drawId: draw.id, drawNumber: draw.drawNumber }));
      const notificationService = new NotificationService(
        notificationRepository,
        makeAPNsClient(env),
      );
      const notificationSummary = await notificationService.notifyEligibleUsers(draw);
      console.log(JSON.stringify({
        event: "notification_run_completed",
        drawId: draw.id,
        ...notificationSummary,
      }));
    } catch (error) {
      logError("draw_update_failed", error);
      throw error;
    }
  },
} satisfies ExportedHandler<Env>;

interface APNsSecretBindings {
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
}

/** Creates an APNs sender only when all required secrets are available. */
function makeAPNsClient(env: Env): APNsClient | null {
  const bindings = env as Env & APNsSecretBindings;
  if (!bindings.APNS_KEY_ID || !bindings.APNS_TEAM_ID || !bindings.APNS_PRIVATE_KEY) {
    return null;
  }

  const configuration: APNsConfiguration = {
    keyId: bindings.APNS_KEY_ID,
    teamId: bindings.APNS_TEAM_ID,
    privateKey: bindings.APNS_PRIVATE_KEY,
    topic: env.APNS_TOPIC,
  };
  return new APNsClient(configuration);
}

/** Writes errors as structured JSON without leaking response bodies. */
function logError(event: string, error: unknown): void {
  const message = error instanceof Error ? error.message : "Unknown error";
  const name = error instanceof Error ? error.name : "UnknownError";
  console.error(JSON.stringify({ event, error: { name, message } }));
}
