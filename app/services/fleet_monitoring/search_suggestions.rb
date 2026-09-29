# Lightweight, categorized autocomplete suggestions for truck_monitoring's
# Command Center search bar. Deliberately does NOT reuse the full
# Vehicle/Hub/PackagePresenter shapes: those run per-record trip/package
# queries (metrics, timelines, capacity) that a keystroke-driven endpoint
# can't afford. Each suggestion carries only the identifier the frontend
# already resolves through its existing selection flow (vehicle `pnr`, hub
# `code`, package `id`) plus a label/detail/status to render the row.
#
# Matching is a case-insensitive substring match on each entity's
# identifier (hubs also match on name); prefix matches rank first. Scope
# mirrors the existing endpoints: POC vehicles only (as /vehicles and
# /search), every hub (as /hubs), every package (as /search/package).
module FleetMonitoring
  class SearchSuggestions
    MIN_QUERY_LENGTH = 3
    DEFAULT_LIMIT = 5
    MAX_LIMIT = 10

    class QueryTooShort < ArgumentError; end

    attr_reader :query, :limit

    def initialize(query, limit: nil)
      @query = query.to_s.strip
      @limit = (limit.presence || DEFAULT_LIMIT).to_i.clamp(1, MAX_LIMIT)
      raise QueryTooShort, "q must be at least #{MIN_QUERY_LENGTH} characters" if @query.length < MIN_QUERY_LENGTH
    end

    def as_json(*)
      {
        query: query,
        limit: limit,
        suggestions: { vehicles: vehicles, hubs: hubs, packages: packages, waybills: waybills }
      }
    end

    private

    def pattern
      @pattern ||= ActiveRecord::Base.sanitize_sql_like(query)
    end

    # Prefix matches before substring matches, then alphabetical.
    def prefix_rank(model, *columns)
      cases = columns.each_with_index.map { |column, index| "WHEN #{column} ILIKE :prefix THEN #{index}" }.join(" ")
      Arel.sql(model.sanitize_sql_array([ "CASE #{cases} ELSE #{columns.size} END", { prefix: "#{pattern}%" } ]))
    end

    def vehicles
      records = Vehicle.fleet_monitoring_poc
                       .includes(:current_geo_location, :vendor_account)
                       .where("vehicles.number ILIKE ?", "%#{pattern}%")
                       .order(prefix_rank(Vehicle, "vehicles.number"), "vehicles.number")
                       .limit(limit)
                       .to_a
      # One batched query instead of VehiclePresenter's per-vehicle trip
      # lookup; the resolver only needs to know whether a trip exists.
      in_transit_ids = Trip.where(vehicle_id: records.map(&:id), status: "in_transit").distinct.pluck(:vehicle_id).to_set

      records.map do |vehicle|
        geo = vehicle.current_geo_location
        {
          kind: "vehicle",
          pnr: vehicle.number,
          label: vehicle.number,
          detail: [ geo && "#{geo.city}, #{geo.state}", vehicle.vendor_account&.name || vehicle.vendor ].compact.join(" · "),
          status: VehicleStatusResolver.resolve(vehicle, current_trip: in_transit_ids.include?(vehicle.id))
        }
      end
    end

    def hubs
      Hub.includes(:geo_location)
         .where("hubs.code ILIKE :q OR hubs.name ILIKE :q", q: "%#{pattern}%")
         .order(prefix_rank(Hub, "hubs.code", "hubs.name"), "hubs.code")
         .limit(limit)
         .map do |hub|
           geo = hub.geo_location
           {
             kind: "hub",
             code: hub.code,
             label: hub.name,
             detail: [ hub.code, geo && "#{geo.city}, #{geo.state}" ].compact.join(" · "),
             status: HubPresenter::STATUS_MAP.fetch(hub.operational_status, "OPERATIONAL")
           }
         end
    end

    def packages
      Package.includes(:location, trip: :vehicle)
             .where("packages.identifier ILIKE ?", "%#{pattern}%")
             .order(prefix_rank(Package, "packages.identifier"), "packages.identifier")
             .limit(limit)
             .map do |package|
               {
                 kind: "package",
                 id: package.identifier,
                 label: package.identifier,
                 detail: package_whereabouts(package),
                 status: PackagePresenter::STATUS_MAP.fetch(package.status, "AT HUB")
               }
             end
    end

    # Waybill numbers match ignoring case and hyphens ("wb0623" ->
    # WB-062320), prefix first; the normalized-prefix LIKE uses
    # index_waybills_on_normalized_number.
    def waybills
      normalized = ActiveRecord::Base.sanitize_sql_like(query.upcase.delete("^A-Z0-9"))
      return [] if normalized.length < MIN_QUERY_LENGTH

      Waybill.includes(:vehicle, :origin_hub, :destination_hub)
             .where("upper(replace(waybills.waybill_number, '-', '')) LIKE ?", "#{normalized}%")
             .order(:waybill_number).limit(limit)
             .map do |waybill|
               {
                 kind: "waybill",
                 waybill_number: waybill.waybill_number,
                 label: waybill.waybill_number,
                 detail: "#{waybill.origin_hub.name} → #{waybill.destination_hub.name} · #{waybill.vehicle.number}",
                 status: waybill.status.upcase.tr("_", " ")
               }
             end
    end

    # Same precedence as PackagePresenter#current_location_label (live
    # vehicle, then hub). Warehouse-located packages get no detail line.
    def package_whereabouts(package)
      return "On #{package.trip.vehicle.number}" if package.trip&.status_in_transit?

      package.location.name if package.location_type == "Hub"
    end
  end
end
