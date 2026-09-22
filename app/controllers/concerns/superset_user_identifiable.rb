# Identifies "the current user" for the notification endpoints only —
# this is intentionally scoped narrowly, not a general auth mechanism for
# the rest of the API (which stays as-is: disabled, see BaseController).
#
# Identity is asserted by the frontend via the `X-Superset-User-Id`
# header, backed by Superset's own already-authenticated session (the
# frontend reads its own logged-in user id from Superset's bootstrap
# data/Redux state — see ARCHITECTURE.md). This app has no shared
# session/cookie with Superset to verify that claim cryptographically
# (different origin, different framework — true SSO would close this gap
# and is out of scope here). When SupersetDirectory is configured, the
# claimed id is at least checked against real Superset users; when it
# isn't (this repo's current state), the header is trusted as given.
#
# EventSource cannot send custom headers, so the SSE stream action uses a
# short-lived signed "ticket" instead (see #issue_sse_ticket) — obtained
# via a header-authenticated request first, then passed as a query param
# only for the SSE connection itself. The ticket is opaque and
# time-limited (not a raw user id), which is the standard pattern for
# this exact EventSource limitation.
module SupersetUserIdentifiable
  extend ActiveSupport::Concern

  UnidentifiedUser = Class.new(StandardError)

  SSE_TICKET_TTL = 60.seconds

  included do
    rescue_from SupersetUserIdentifiable::UnidentifiedUser, with: :render_unidentified_user
  end

  private

  def current_superset_user_id
    id = request.headers["X-Superset-User-Id"].presence
    raise UnidentifiedUser if id.blank?
    raise UnidentifiedUser if SupersetDirectory.configured? && SupersetDirectory.find_user(id).blank?

    id.to_i
  end

  def issue_sse_ticket(user_id)
    sse_ticket_verifier.generate({ "user_id" => user_id }, expires_in: SSE_TICKET_TTL, purpose: :sse_notifications)
  end

  def verify_sse_ticket(ticket)
    return nil if ticket.blank?

    sse_ticket_verifier.verify(ticket, purpose: :sse_notifications)
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def sse_ticket_verifier
    Rails.application.message_verifier(:sse_notifications)
  end

  def render_unidentified_user
    render json: { error: "Missing or unrecognized X-Superset-User-Id" }, status: :unauthorized
  end
end
