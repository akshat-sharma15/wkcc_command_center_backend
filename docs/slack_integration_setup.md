# Slack Integration Setup

How to connect this API to Slack for alert delivery, per environment.
Relevant code: [SlackOauthClient](../app/services/slack_oauth_client.rb),
[SlackIntegrationsController](../app/controllers/api/v1/slack_integrations_controller.rb),
[NotificationDeliveryJob](../app/jobs/notification_delivery_job.rb).

## 0. Prerequisite: Rails encryption credentials

`Integration#bot_token` is stored encrypted (`ActiveRecord::Encryption`),
which needs its own per-environment keys in Rails credentials — separate
from `.env`. If this hasn't been set up yet on the environment you're
connecting Slack on, step 3 below will fail with
`ActiveRecord::Encryption::Errors::Configuration`. See
`DEVELOPMENT_SETUP.md` step 4b for the one-time setup command.

## 1. Create the Slack App

1. Go to https://api.slack.com/apps → **Create New App** → From scratch.
2. Under **OAuth & Permissions**:
   - Add the `chat:write` bot token scope (under *Bot Token Scopes*).
   - Add a **Redirect URL** for every environment that will complete the
     OAuth flow, pointing at that environment's `/callback` endpoint —
     nothing else. Example:
     - `http://localhost:3001/api/v1/integrations/slack/callback` (local dev)
     - `http://182.156.33.77:9012/api/v1/integrations/slack/callback` (this prod host)
   - Do **not** register `/integrations/slack/connect` as a redirect URL —
     that endpoint only *generates* the authorization URL; Slack never
     redirects back to it.
3. Note the **Client ID** and **Client Secret** from *Basic Information* →
   *App Credentials*.

## 2. Set environment variables (per environment)

```
SLACK_CLIENT_ID=<from Slack app>
SLACK_CLIENT_SECRET=<from Slack app>        # never commit this
SLACK_REDIRECT_URI=<this environment's exact /callback URL>
SLACK_NOTIFICATION_CHANNEL=<channel id or #name>
FRONTEND_BASE_URL=<origin the browser should land back on after connecting>
```

`SLACK_REDIRECT_URI` must be **byte-for-byte identical** to one of the
Redirect URLs registered in step 1, and must match the host the API is
actually running on for that environment — copying the local dev value to
prod (or vice versa) is the most common way to break this.

All three of `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET`, and
`SLACK_REDIRECT_URI` must be set or `GET /api/v1/integrations/slack/connect`
returns `503 { error: "Slack is not configured on this server" }`
(`SlackOauthClient.configured?`).

Restart the app after changing env vars — Rails reads `ENV` at request
time here, but most deploy setups still require a process restart to pick
up new environment variables.

## 3. Connect the workspace

1. Frontend calls `GET /api/v1/integrations/slack/connect`, gets back
   `{ authorization_url: "..." }`, and navigates the browser there.
2. User approves the app in Slack.
3. Slack redirects to `GET /api/v1/integrations/slack/callback`, which
   exchanges the code for a bot token and upserts a single `Integration`
   row (`provider: "slack"`), then redirects the browser to
   `FRONTEND_BASE_URL + /integration/list/?slack=success|error`.

Check connection status any time with `GET /api/v1/integrations/slack`.

## 4. Invite the bot to the notification channel

`chat:write` alone does not let the bot post into a channel it hasn't
been added to. In Slack, run `/invite @YourBotName` in whatever channel
`SLACK_NOTIFICATION_CHANNEL` points at. If the bot isn't in the channel,
delivery fails cleanly (`Notification.status = "failed"`), not silently.

## 5. Verifying from `rails c`

```ruby
SlackOauthClient.configured?              # must be true before /connect will work
ENV["SLACK_CLIENT_ID"]
ENV["SLACK_REDIRECT_URI"]                 # compare against the Slack app's registered Redirect URLs
ENV["SLACK_CLIENT_SECRET"].present?       # don't print the actual secret

Integration.find_by(provider: "slack")    # nil until a successful OAuth callback has run
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| `503` on `/connect` | One of `SLACK_CLIENT_ID`/`SLACK_CLIENT_SECRET`/`SLACK_REDIRECT_URI` isn't set in that environment |
| `Integration.all` is `[]` | Expected until OAuth has completed successfully at least once — it isn't seeded |
| `404` on any `/api/v1/notifications*` route | That route isn't deployed yet — check the running commit includes the notifications feature and its migrations have been run |
| CORS error in browser console | Frontend origin isn't in `CORS_ALLOWED_ORIGINS` on that environment (see [cors.rb](../config/initializers/cors.rb)) |
| Callback redirects to `slack=error&reason=invalid_state` | OAuth state expired or was already used — restart the connect flow |
| Callback redirects to `slack=error&reason=slack_unreachable` | Network failure calling Slack's token endpoint — check outbound connectivity from the server |
| `ActiveRecord::Encryption::Errors::Configuration: Missing Active Record encryption credential` on the callback | This environment's Rails credentials don't have an `active_record_encryption` block yet — see step 0 / `DEVELOPMENT_SETUP.md` step 4b |
| `Couldn't decrypt config/credentials.yml.enc. Perhaps you passed the wrong key?` while trying to fix the above | `config/master.key` on this server doesn't match the key `credentials.yml.enc` was originally encrypted with (or doesn't exist yet — check whatever starts the process, e.g. `systemctl cat <service>`, for a `RAILS_MASTER_KEY`/`EnvironmentFile` you may have missed). If the original key is genuinely unrecoverable and no Slack integration has ever been successfully saved on that server yet (check `Integration.where(provider: "slack").exists?` — the failing callback never got that far), it's safe to `rm config/master.key config/credentials.yml.enc` and run `rails credentials:edit` again to scaffold a fresh one from zero, re-adding the `active_record_encryption` block. Back the new `config/master.key` up somewhere durable immediately after. |
| Bot connects but Slack delivery fails with `not_in_channel` | The bot token is valid but hasn't been invited to the channel `SLACK_NOTIFICATION_CHANNEL` points at — see step 4 above |
