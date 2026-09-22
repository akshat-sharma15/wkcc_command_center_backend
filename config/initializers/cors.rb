# Handles Cross-Origin Resource Sharing for browser-based clients (the
# Superset/Webkorps Command Center frontend at localhost:9000 is the
# expected consumer of the Stage 3+ SSE stream, on a different origin than
# this API's own dev server at localhost:3001).
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins ENV.fetch("CORS_ALLOWED_ORIGINS", "*").split(",")

    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head]
  end
end
