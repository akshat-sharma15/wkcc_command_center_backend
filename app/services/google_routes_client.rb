# Server-side call to the Google Routes API (computeRoutes), used only by
# FleetMonitoring::RoadRouteService to fill the road_routes table. Plain
# Net::HTTP, same convention as GeminiClient. GOOGLE_ROUTES_API_KEY is read
# here only and never logged or returned.
require "net/http"
require "uri"
require "json"

class GoogleRoutesClient
  ENDPOINT = "https://routes.googleapis.com/directions/v2:computeRoutes".freeze
  FIELD_MASK = "routes.polyline.encodedPolyline,routes.distanceMeters".freeze
  REQUEST_TIMEOUT = 15

  ApiError = Class.new(StandardError)

  def self.configured?
    ENV["GOOGLE_ROUTES_API_KEY"].present?
  end

  def initialize(api_key: ENV["GOOGLE_ROUTES_API_KEY"])
    raise ApiError, "GOOGLE_ROUTES_API_KEY is not set" if api_key.blank?

    @api_key = api_key
  end

  # waypoints: [{ lat:, lng: }, ...] - first is the origin, last the
  # destination, any in between are pass-through (via) points.
  # Returns { encoded_polyline:, distance_meters: }.
  def compute_route(waypoints)
    raise ArgumentError, "a route needs at least 2 waypoints" if waypoints.size < 2

    body = {
      origin: location(waypoints.first),
      destination: location(waypoints.last),
      intermediates: waypoints[1...-1].map { |p| location(p).merge(via: true) },
      travelMode: "DRIVE"
    }
    route = post(body).dig("routes", 0)
    polyline = route&.dig("polyline", "encodedPolyline")
    raise ApiError, "Google Routes API returned no route" if polyline.blank?

    { encoded_polyline: polyline, distance_meters: route["distanceMeters"] }
  end

  private

  def location(point)
    { location: { latLng: { latitude: point[:lat].to_f, longitude: point[:lng].to_f } } }
  end

  def post(body)
    uri = URI(ENDPOINT)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = REQUEST_TIMEOUT
    http.read_timeout = REQUEST_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Goog-Api-Key"] = @api_key
    request["X-Goog-FieldMask"] = FIELD_MASK
    request.body = body.to_json

    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      raise ApiError, "Google Routes API error (HTTP #{response.code}): #{error_message_from(response)}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise ApiError, "Google Routes API returned an unparseable response: #{e.class}"
  rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
    raise ApiError, "Google Routes API request failed: #{e.class}: #{e.message}"
  end

  def error_message_from(response)
    JSON.parse(response.body).dig("error", "message") || response.body.to_s.truncate(200)
  rescue JSON::ParserError
    response.body.to_s.truncate(200)
  end
end
