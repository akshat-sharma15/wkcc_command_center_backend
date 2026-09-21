# Short-lived CSRF token for the Slack OAuth handshake. DB-backed rather
# than session/cookie-based deliberately: the frontend (localhost:9000)
# and this API (localhost:3001) are different origins with no shared
# cookie domain, and the callback is a real cross-site browser redirect
# from slack.com — a `SameSite=None` cookie would need HTTPS to survive
# that round-trip, which local dev doesn't have. The state token itself,
# round-tripped by Slack in the callback query string, is the credential;
# looking it up here needs no cookie at all.
class CreateSlackOauthStates < ActiveRecord::Migration[8.1]
  def change
    create_table :slack_oauth_states do |t|
      t.string :state, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :slack_oauth_states, :state, unique: true
  end
end
