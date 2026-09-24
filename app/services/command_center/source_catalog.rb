module CommandCenter
  # The AI chatbot's server-side catalog of every approved data source
  # (Phase 5). This is how the model is "taught" the schema, rather than
  # relying on it to guess column meanings or discover tables on its own
  # - see CommandCenter::QueryService, which validates every request
  # against exactly this list, and CommandCenter::SchemaIntrospectionService,
  # which cross-checks it against the live database.
  #
  # Views come first deliberately (see SourceCatalog::VIEW_SOURCES /
  # TABLE_SOURCES) - the analytical views are the PRIMARY source; raw
  # tables are only for operational event history, package status
  # history, or drill-down detail the views don't expose.
  module SourceCatalog
    Column = Struct.new(:name, :type, :description, keyword_init: true)

    Source = Struct.new(
      :name, :kind, :purpose, :grain, :columns, :safe_aggregations,
      :date_columns, :relationships, :example_questions,
      keyword_init: true
    ) do
      def column_names
        columns.map(&:name)
      end
    end

    def self.col(name, type, description)
      Column.new(name: name.to_s, type: type, description: description)
    end

    VIEW_SOURCES = {
      "vw_hub_dashboard_summary" => Source.new(
        name: "vw_hub_dashboard_summary",
        kind: :view,
        purpose: "Current operational snapshot for every hub: capacity, parking, " \
                 "fleet presence, trip activity, package/backlog, hub-event counts, " \
                 "dwell/turnaround, and hub-scoped alerts.",
        grain: "one row per hub",
        columns: [
          col(:hub_id, :integer, "Hub's primary key. Join key to hubs.id."),
          col(:hub_code, :string, "Hub's short code, e.g. CC-HUB-012."),
          col(:hub_name, :string, "Hub's display name, e.g. 'Indore Command Centre Hub'."),
          col(:location, :string, "Free-text city/region description of the hub."),
          col(:operational_status, :string, "One of: active, degraded, closed."),
          col(:capacity, :integer, "Hub's total rated capacity."),
          col(:parking_capacity, :integer, "Total parking slots at the hub."),
          col(:available_parking, :integer, "Currently free parking slots."),
          col(:parking_utilisation_pct, :decimal, "% of parking slots occupied = (parking_capacity - available_parking) / parking_capacity * 100."),
          col(:total_vehicles, :integer, "Vehicles whose home hub is this hub (vehicles.hub_id)."),
          col(:active_vehicles, :integer, "Of total_vehicles, count with status = active."),
          col(:inbound_vehicle_count, :integer, "All-time count of GATE_IN hub_operations_events at this hub."),
          col(:outbound_vehicle_count, :integer, "All-time count of DEPARTED hub_operations_events at this hub."),
          col(:active_trips, :integer, "Trips with status=in_transit touching this hub (as origin or destination)."),
          col(:completed_trips, :integer, "Trips with status=completed touching this hub."),
          col(:delayed_trips, :integer, "Trips with status=delayed touching this hub."),
          col(:package_count, :integer, "Packages currently located at this hub (packages.location_type='Hub')."),
          col(:packages_in_transit, :integer, "Of package_count, status=in_transit."),
          col(:delivered_packages, :integer, "Of package_count, status=delivered."),
          col(:backlog_packages, :integer, "Of package_count, status IN (pending, received) - awaiting processing/dispatch."),
          col(:damaged_quantity, :integer, "Sum of packages.damaged_quantity for packages at this hub."),
          col(:short_quantity, :integer, "Sum of packages.short_quantity for packages at this hub."),
          col(:processed_event_count, :integer, "All-time SCANNED+SORTED hub_operations_events at this hub."),
          col(:dispatch_ready_count, :integer, "All-time DISPATCH_READY hub_operations_events at this hub."),
          col(:packages_scanned_count, :integer, "Distinct packages with a SCANNED hub_operations_event at this hub - a throughput proxy."),
          col(:avg_dwell_time_minutes, :decimal, "Average minutes between a vehicle's GATE_IN and DEPARTED hub_operations_events. NULL if no such event pairs exist yet - do not guess a number when NULL."),
          col(:avg_vehicle_turnaround_minutes, :decimal, "Average minutes between a vehicle's trip arrival at this hub and its next trip departure from this hub (derived from trips, not events)."),
          col(:open_alerts, :integer, "Open alerts where alerts.group='hubs' and record_id=this hub."),
          col(:critical_alerts, :integer, "Of open_alerts, severity=critical.")
        ],
        safe_aggregations: %w[capacity parking_capacity available_parking parking_utilisation_pct total_vehicles active_vehicles
                               inbound_vehicle_count outbound_vehicle_count active_trips completed_trips delayed_trips
                               package_count packages_in_transit delivered_packages backlog_packages damaged_quantity
                               short_quantity processed_event_count dispatch_ready_count packages_scanned_count
                               avg_dwell_time_minutes avg_vehicle_turnaround_minutes open_alerts critical_alerts],
        date_columns: [],
        relationships: "hub_id joins to hubs.id, vehicles.hub_id, trips.origin_hub_id/destination_hub_id, packages.location_id (when location_type='Hub').",
        example_questions: [
          "How many trucks are currently at Indore hub?",
          "What is the average waiting time at Indore hub?",
          "Which hubs have the highest backlog?",
          "What is happening at Indore hub?",
          "Why is Indore hub showing operational pressure?"
        ]
      ),

      "vw_hub_dashboard_overview" => Source.new(
        name: "vw_hub_dashboard_overview",
        kind: :view,
        purpose: "Network-wide hub totals, built by summing vw_hub_dashboard_summary.",
        grain: "exactly one row - the whole network",
        columns: [
          col(:total_hubs, :integer, "Count of all hubs."),
          col(:active_hubs, :integer, "Hubs with operational_status=active."),
          col(:total_vehicles, :integer, "Network-wide vehicle count."),
          col(:active_vehicles, :integer, "Network-wide active-status vehicle count."),
          col(:total_packages, :integer, "Network-wide packages currently at any hub."),
          col(:packages_in_transit, :integer, "Of total_packages, status=in_transit."),
          col(:total_backlog, :integer, "Sum of backlog_packages across all hubs."),
          col(:total_open_alerts, :integer, "Sum of open hub-group alerts across all hubs."),
          col(:total_critical_alerts, :integer, "Sum of critical open hub-group alerts across all hubs."),
          col(:average_dwell_time_minutes, :decimal, "Unweighted average of avg_dwell_time_minutes across hubs that have dwell data. NULL if none do."),
          col(:throughput_packages_scanned, :integer, "Sum of packages_scanned_count across all hubs.")
        ],
        safe_aggregations: [], # already a single-row network aggregate - do not aggregate further
        date_columns: [],
        relationships: "No join key - this is a pre-aggregated one-row summary of vw_hub_dashboard_summary.",
        example_questions: [
          "What are the current fleet numbers?",
          "How many hubs are active?",
          "What is the total package backlog across the network?"
        ]
      ),

      "vw_fleet_dashboard_summary" => Source.new(
        name: "vw_fleet_dashboard_summary",
        kind: :view,
        purpose: "Network-wide fleet totals: vehicle availability, mileage, fuel efficiency, trip activity, breakdown/deviation counts.",
        grain: "exactly one row - the whole network",
        columns: [
          col(:total_vehicles, :integer, "Count of all vehicles."),
          col(:active_vehicles, :integer, "Vehicles with status=active."),
          col(:inactive_vehicles, :integer, "Vehicles with status != active (maintenance or out_of_service)."),
          col(:vehicles_on_trip, :integer, "Vehicles with at least one trip currently status=in_transit."),
          col(:vehicles_available, :integer, "Active-status vehicles with no in_transit trip right now."),
          col(:average_mileage_km, :decimal, "Average vehicles.mileage_km across all vehicles."),
          col(:average_fuel_efficiency_kmpl, :decimal, "Average vehicles.fuel_efficiency_kmpl across all vehicles."),
          col(:active_trips, :integer, "Trips with status=in_transit."),
          col(:delayed_trips, :integer, "Trips with status=delayed."),
          col(:completed_trips, :integer, "Trips with status=completed."),
          col(:breakdown_count, :integer, "All-time count of BREAKDOWN vehicle_operation_events."),
          col(:route_deviation_count, :integer, "All-time count of ROUTE_DEVIATION vehicle_operation_events.")
        ],
        safe_aggregations: [],
        date_columns: [],
        relationships: "No join key - a pre-aggregated one-row fleet summary.",
        example_questions: [
          "What is the average mileage of the fleet?",
          "What is the average fuel efficiency?",
          "How many vehicles are currently on trip?",
          "Which vehicles have breakdowns?"
        ]
      ),

      "vw_vehicle_dashboard" => Source.new(
        name: "vw_vehicle_dashboard",
        kind: :view,
        purpose: "Current operational detail for every vehicle: identity, location, fleet metrics, home hub, driver, current trip, and package/order counts on that trip.",
        grain: "one row per vehicle",
        columns: [
          col(:vehicle_id, :integer, "Vehicle's primary key. Join key to vehicles.id."),
          col(:vehicle_number, :string, "Vehicle's display number, e.g. CC-VEH-0074."),
          col(:vehicle_type, :string, "Free-text type, e.g. truck, mini_truck, trailer, van."),
          col(:vendor, :string, "Owning/leasing vendor name."),
          col(:status, :string, "One of: active, maintenance, out_of_service."),
          col(:current_location, :string, "Human-readable current location string (not coordinates)."),
          col(:last_known_latitude, :decimal, "Last known GPS latitude. NULL if never recorded."),
          col(:last_known_longitude, :decimal, "Last known GPS longitude. NULL if never recorded."),
          col(:last_location_at, :datetime, "Timestamp the last known coordinates were recorded."),
          col(:capacity, :integer, "Vehicle's load capacity."),
          col(:mileage_km, :decimal, "Vehicle's current odometer-style mileage reading."),
          col(:fuel_efficiency_kmpl, :decimal, "Vehicle's fuel efficiency in km per litre."),
          col(:hub_id, :integer, "Vehicle's home/assigned hub id."),
          col(:hub_code, :string, "Home hub's code."),
          col(:hub_name, :string, "Home hub's name - 'vehicles at <hub>' means hub_name/hub_code equals the asked hub."),
          col(:driver_id, :integer, "Assigned driver's id (workforce_members.id), if any."),
          col(:driver_identifier, :string, "Assigned driver's identifier."),
          col(:driver_name, :string, "Assigned driver's name."),
          col(:trip_id, :integer, "The vehicle's CURRENT trip id - only set if it has a trip with status=in_transit right now. NULL means no active trip."),
          col(:origin_hub_id, :integer, "Current trip's origin hub id."),
          col(:origin_hub, :string, "Current trip's origin hub name."),
          col(:destination_hub_id, :integer, "Current trip's destination hub id."),
          col(:destination_hub, :string, "Current trip's destination hub name."),
          col(:departure_at, :datetime, "Current trip's departure timestamp."),
          col(:expected_arrival_at, :datetime, "Current trip's expected arrival timestamp."),
          col(:actual_arrival_at, :datetime, "Current trip's actual arrival timestamp (NULL while in transit)."),
          col(:trip_status, :string, "Current trip's status - always in_transit when trip_id is set, by construction."),
          col(:package_count, :integer, "Packages on the vehicle's current trip. 0 if no current trip."),
          col(:order_count, :integer, "Distinct orders represented among those packages."),
          col(:breakdown_count, :integer, "All-time BREAKDOWN vehicle_operation_events for this vehicle."),
          col(:route_deviation_count, :integer, "All-time ROUTE_DEVIATION vehicle_operation_events for this vehicle."),
          col(:open_alert_count, :integer, "Open alerts where group='vehicles' and record_id=this vehicle."),
          col(:critical_alert_count, :integer, "Of open_alert_count, severity=critical.")
        ],
        safe_aggregations: %w[capacity mileage_km fuel_efficiency_kmpl package_count order_count breakdown_count route_deviation_count open_alert_count critical_alert_count],
        date_columns: %w[last_location_at departure_at expected_arrival_at actual_arrival_at],
        relationships: "vehicle_id joins to vehicles.id. hub_id/hub_code/hub_name identify the vehicle's HOME hub (not necessarily where it physically is right now - use current_location or last_known_latitude/longitude for that, or origin_hub/destination_hub for its current trip).",
        example_questions: [
          "Which vehicles are currently at Indore?",
          "How many vehicles are currently at Indore hub?",
          "Which vehicles are carrying packages?",
          "Show me the packages currently assigned to CC-VEH-0074.",
          "Which vehicles are travelling from Indore to Pune?",
          "Which vehicles have breakdown events?"
        ]
      ),

      "vw_route_dashboard" => Source.new(
        name: "vw_route_dashboard",
        kind: :view,
        purpose: "Trip-level detail: route, timing, duration, ETA variance, and package/order/exception counts for that trip. Trip is the route/trip source - there is no separate routes table.",
        grain: "one row per trip",
        columns: [
          col(:trip_id, :integer, "Trip's primary key. Join key to trips.id."),
          col(:vehicle_id, :integer, "Assigned vehicle's id."),
          col(:vehicle_number, :string, "Assigned vehicle's display number."),
          col(:origin_hub_id, :integer, "Origin hub id."),
          col(:origin_hub, :string, "Origin hub name."),
          col(:destination_hub_id, :integer, "Destination hub id."),
          col(:destination_hub, :string, "Destination hub name."),
          col(:status, :string, "One of: scheduled, in_transit, completed, cancelled, delayed."),
          col(:departure_at, :datetime, "Departure timestamp."),
          col(:expected_arrival_at, :datetime, "Expected arrival timestamp."),
          col(:actual_arrival_at, :datetime, "Actual arrival timestamp. NULL until the trip actually arrives."),
          col(:trip_duration_minutes, :decimal, "actual_arrival_at - departure_at, in minutes. NULL until both exist."),
          col(:eta_variance_minutes, :decimal, "actual_arrival_at - expected_arrival_at, in minutes. Positive = late, negative = early. NULL until actual_arrival_at exists - 'delayed'/'late' should be read from this or from status=delayed, never guessed."),
          col(:package_count, :integer, "Packages assigned to this trip."),
          col(:order_count, :integer, "Distinct orders among those packages."),
          col(:breakdown_count, :integer, "BREAKDOWN vehicle_operation_events scoped to this trip."),
          col(:route_deviation_count, :integer, "ROUTE_DEVIATION vehicle_operation_events scoped to this trip.")
        ],
        safe_aggregations: %w[trip_duration_minutes eta_variance_minutes package_count order_count breakdown_count route_deviation_count],
        date_columns: %w[departure_at expected_arrival_at actual_arrival_at],
        relationships: "trip_id joins to trips.id. No alert columns - Trip is deliberately excluded from the alert system.",
        example_questions: [
          "Which trips are delayed?",
          "Which route has the most packages?",
          "Which vehicles are travelling from Indore to Pune?",
          "Which delayed trips have the most packages?"
        ]
      ),

      "vw_shipment_dashboard_summary" => Source.new(
        name: "vw_shipment_dashboard_summary",
        kind: :view,
        purpose: "Network-wide order/package totals: status breakdown, SLA coverage, overdue/late counts, package-scoped alerts.",
        grain: "exactly one row - the whole network",
        columns: [
          col(:total_orders, :integer, "Count of all orders."),
          col(:total_packages, :integer, "Count of all packages."),
          col(:packages_in_transit, :integer, "Packages with status=in_transit."),
          col(:packages_delivered, :integer, "Packages with status=delivered."),
          col(:packages_pending, :integer, "Packages with status=pending."),
          col(:packages_damaged, :integer, "Packages with status=damaged (the status ENUM value, not a nonzero damaged_quantity in another status)."),
          col(:packages_short, :integer, "Packages with status=short."),
          col(:promised_deliveries, :integer, "Packages that HAVE a promised_delivery_at set - SLA coverage, not an on-time count."),
          col(:overdue_packages, :integer, "Packages with promised_delivery_at set, not yet delivered, and past that date."),
          col(:delivered_late_packages, :integer, "Packages delivered after their promised_delivery_at."),
          col(:open_package_alerts, :integer, "Open alerts where group='packages'."),
          col(:critical_package_alerts, :integer, "Of open_package_alerts, severity=critical.")
        ],
        safe_aggregations: [],
        date_columns: [],
        relationships: "No join key - a pre-aggregated one-row shipment summary.",
        example_questions: [
          "How many orders are pending?",
          "How many packages are currently in transit?",
          "How many packages are overdue?",
          "How many packages are damaged?",
          "How many packages are delivered?"
        ]
      ),

      "vw_shipment_dashboard" => Source.new(
        name: "vw_shipment_dashboard",
        kind: :view,
        purpose: "Package-level detail: order context, delivery dates, resolved location, trip/vehicle/route context, alerts, and latest status-change time.",
        grain: "one row per package",
        columns: [
          col(:package_id, :integer, "Package's primary key. Join key to packages.id."),
          col(:package_identifier, :string, "Package's display identifier, e.g. CC-PKG-000123."),
          col(:package_status, :string, "One of: pending, in_transit, received, damaged, short, delivered."),
          col(:expected_quantity, :integer, "Expected item quantity."),
          col(:received_quantity, :integer, "Actually received quantity."),
          col(:damaged_quantity, :integer, "Quantity recorded as damaged."),
          col(:short_quantity, :integer, "Quantity recorded as short/missing."),
          col(:promised_delivery_at, :datetime, "Package's own promise if set, else its order's promise."),
          col(:delivered_at, :datetime, "Actual delivery timestamp. NULL unless package_status=delivered."),
          col(:location_id, :integer, "Current location's id (polymorphic with location_type)."),
          col(:location_type, :string, "Either 'Hub' or 'Warehouse'."),
          col(:location_name, :string, "Resolved name of the current location, whichever type it is."),
          col(:order_id, :integer, "Owning order's id, if any."),
          col(:order_number, :string, "Owning order's display number."),
          col(:customer_reference, :string, "Owning order's customer reference."),
          col(:order_status, :string, "Owning order's status."),
          col(:trip_id, :integer, "Assigned trip's id, if any."),
          col(:vehicle_id, :integer, "Assigned trip's vehicle id."),
          col(:vehicle_number, :string, "Assigned trip's vehicle number."),
          col(:origin_hub, :string, "Assigned trip's origin hub name."),
          col(:destination_hub, :string, "Assigned trip's destination hub name."),
          col(:trip_status, :string, "Assigned trip's status."),
          col(:open_alert_count, :integer, "Open alerts where group='packages' and record_id=this package."),
          col(:critical_alert_count, :integer, "Of open_alert_count, severity=critical."),
          col(:latest_status_transition_at, :datetime, "Most recent package_status_transitions.occurred_at for this package. NULL if no transition has been recorded yet.")
        ],
        safe_aggregations: %w[expected_quantity received_quantity damaged_quantity short_quantity open_alert_count critical_alert_count],
        date_columns: %w[promised_delivery_at delivered_at latest_status_transition_at],
        relationships: "package_id joins to packages.id. order_id joins to orders.id. trip_id joins to trips.id. This is the primary source for 'packages on vehicle X' (filter vehicle_number) and 'packages at hub X' (filter location_name / destination_hub).",
        example_questions: [
          "Show me the packages currently assigned to CC-VEH-0074.",
          "Which packages are assigned to vehicle CC-VEH-0074?",
          "How many packages are currently at Indore?"
        ]
      ),

      "vw_network_health_summary" => Source.new(
        name: "vw_network_health_summary",
        kind: :view,
        purpose: "A trusted network-wide snapshot combining hub, fleet, and shipment totals plus all-group alert counts. NOT a weighted health score - there is no single 'health number'.",
        grain: "exactly one row - the whole network",
        columns: [
          col(:total_hubs, :integer, "Count of all hubs."),
          col(:active_hubs, :integer, "Hubs with operational_status=active."),
          col(:total_vehicles, :integer, "Count of all vehicles."),
          col(:active_vehicles, :integer, "Vehicles with status=active."),
          col(:vehicles_on_trip, :integer, "Vehicles with a currently in_transit trip."),
          col(:active_trips, :integer, "Trips with status=in_transit."),
          col(:delayed_trips, :integer, "Trips with status=delayed."),
          col(:total_orders, :integer, "Count of all orders."),
          col(:total_packages, :integer, "Count of all packages."),
          col(:packages_in_transit, :integer, "Packages with status=in_transit."),
          col(:delivered_packages, :integer, "Packages with status=delivered."),
          col(:open_alerts, :integer, "Open alerts across ALL groups (hubs, vehicles, packages, payments, workforce, event-mode)."),
          col(:critical_alerts, :integer, "Of open_alerts, severity=critical."),
          col(:average_fuel_efficiency_kmpl, :decimal, "Network-wide average vehicles.fuel_efficiency_kmpl."),
          col(:average_mileage_km, :decimal, "Network-wide average vehicles.mileage_km.")
        ],
        safe_aggregations: [],
        date_columns: [],
        relationships: "No join key - a pre-aggregated one-row network snapshot, composed from vw_hub_dashboard_overview + vw_fleet_dashboard_summary + vw_shipment_dashboard_summary plus a fresh all-group alert count.",
        example_questions: [
          "What are the current fleet numbers?",
          "How many critical alerts are open?",
          "Give me an overall network snapshot."
        ]
      )
    }.freeze

    TABLE_SOURCES = {
      "hubs" => Source.new(
        name: "hubs", kind: :table,
        purpose: "Raw hub records. Prefer vw_hub_dashboard_summary for anything operational - use this table only when you need a plain hub lookup/list not covered by the view.",
        grain: "one row per hub",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:code, :string, "Short unique code."),
          col(:name, :string, "Display name."),
          col(:location, :string, "Free-text location."),
          col(:capacity, :integer, "Total rated capacity."),
          col(:parking_capacity, :integer, "Total parking slots."),
          col(:available_parking, :integer, "Currently free parking slots."),
          col(:operational_status, :string, "One of: active, degraded, closed."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: %w[capacity parking_capacity available_parking],
        date_columns: %w[created_at updated_at],
        relationships: "id is referenced by vehicles.hub_id, trips.origin_hub_id/destination_hub_id, orders.origin_hub_id/destination_hub_id, workforce_members.hub_id, hub_operations_events.hub_id.",
        example_questions: [ "List all hubs and their operational status." ]
      ),

      "vehicles" => Source.new(
        name: "vehicles", kind: :table,
        purpose: "Raw vehicle records. Prefer vw_vehicle_dashboard for anything operational (current trip, packages, alerts) - use this table only for a plain vehicle lookup.",
        grain: "one row per vehicle",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:number, :string, "Display number, e.g. CC-VEH-0074."),
          col(:vehicle_type, :string, "Free-text type."),
          col(:status, :string, "One of: active, maintenance, out_of_service."),
          col(:capacity, :integer, "Load capacity."),
          col(:vendor, :string, "Owning/leasing vendor."),
          col(:current_location, :string, "Human-readable current location string."),
          col(:hub_id, :integer, "Home hub id."),
          col(:driver_id, :integer, "Assigned driver's workforce_members.id, if any."),
          col(:last_known_latitude, :decimal, "Last known GPS latitude."),
          col(:last_known_longitude, :decimal, "Last known GPS longitude."),
          col(:last_location_at, :datetime, "When last known coordinates were recorded."),
          col(:mileage_km, :decimal, "Current mileage reading."),
          col(:fuel_efficiency_kmpl, :decimal, "Fuel efficiency in km/l."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: %w[capacity mileage_km fuel_efficiency_kmpl],
        date_columns: %w[last_location_at created_at updated_at],
        relationships: "id is referenced by trips.vehicle_id, hub_operations_events.vehicle_id, vehicle_operation_events.vehicle_id. hub_id joins to hubs.id. driver_id joins to workforce_members.id.",
        example_questions: [ "List vehicles with status out_of_service." ]
      ),

      "trips" => Source.new(
        name: "trips", kind: :table,
        purpose: "Raw trip records. Prefer vw_route_dashboard for anything operational (duration, ETA variance, package counts) - use this table only for a plain trip lookup.",
        grain: "one row per trip",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:vehicle_id, :integer, "Assigned vehicle id."),
          col(:origin_hub_id, :integer, "Origin hub id."),
          col(:destination_hub_id, :integer, "Destination hub id."),
          col(:departure_at, :datetime, "Departure timestamp."),
          col(:expected_arrival_at, :datetime, "Expected arrival timestamp."),
          col(:actual_arrival_at, :datetime, "Actual arrival timestamp."),
          col(:status, :string, "One of: scheduled, in_transit, completed, cancelled, delayed."),
          col(:route_info, :text, "Free-text route description."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: [],
        date_columns: %w[departure_at expected_arrival_at actual_arrival_at created_at updated_at],
        relationships: "id is referenced by packages.trip_id, hub_operations_events.trip_id, vehicle_operation_events.trip_id. vehicle_id/origin_hub_id/destination_hub_id join to vehicles.id/hubs.id.",
        example_questions: [ "How many trips departed from Indore this month?" ]
      ),

      "packages" => Source.new(
        name: "packages", kind: :table,
        purpose: "Raw package records. Prefer vw_shipment_dashboard for anything operational (order/trip/location context, alerts) - use this table only for a plain package lookup or quantity aggregation.",
        grain: "one row per package",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:identifier, :string, "Display identifier, e.g. CC-PKG-000123."),
          col(:trip_id, :integer, "Assigned trip id, if any."),
          col(:location_type, :string, "Either 'Hub' or 'Warehouse'."),
          col(:location_id, :integer, "Current location's id (polymorphic with location_type)."),
          col(:order_id, :integer, "Owning order id, if any."),
          col(:expected_quantity, :integer, "Expected item quantity."),
          col(:received_quantity, :integer, "Received quantity."),
          col(:damaged_quantity, :integer, "Damaged quantity."),
          col(:short_quantity, :integer, "Short/missing quantity."),
          col(:status, :string, "One of: pending, in_transit, received, damaged, short, delivered."),
          col(:promised_delivery_at, :datetime, "Package's own promised delivery time, if set."),
          col(:delivered_at, :datetime, "Actual delivery timestamp."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: %w[expected_quantity received_quantity damaged_quantity short_quantity],
        date_columns: %w[promised_delivery_at delivered_at created_at updated_at],
        relationships: "id is referenced by package_status_transitions.package_id, hub_operations_events.package_id. trip_id joins to trips.id. order_id joins to orders.id.",
        example_questions: [ "How many packages have nonzero damaged_quantity?" ]
      ),

      "orders" => Source.new(
        name: "orders", kind: :table,
        purpose: "Raw order records - the customer-facing shipment header above packages.",
        grain: "one row per order",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:order_number, :string, "Display number, e.g. CC-ORD-001234."),
          col(:customer_reference, :string, "Free-text customer reference."),
          col(:status, :string, "One of: pending, processing, in_transit, delivered, cancelled."),
          col(:priority, :string, "Free-text priority label, e.g. standard, high, urgent, low."),
          col(:origin_hub_id, :integer, "Origin hub id, if set."),
          col(:destination_hub_id, :integer, "Destination hub id, if set."),
          col(:package_count, :integer, "Number of packages under this order."),
          col(:total_weight, :decimal, "Total order weight, if set."),
          col(:promised_delivery_at, :datetime, "Order-level promised delivery time."),
          col(:delivered_at, :datetime, "Order-level actual delivery time, if set."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: %w[package_count total_weight],
        date_columns: %w[promised_delivery_at delivered_at created_at updated_at],
        relationships: "id is referenced by packages.order_id. origin_hub_id/destination_hub_id join to hubs.id.",
        example_questions: [ "How many orders are pending?", "How many orders have priority=urgent?" ]
      ),

      "hub_operations_events" => Source.new(
        name: "hub_operations_events", kind: :table,
        purpose: "Operational event history for hubs (gate-in, unloading, scanning, sorting, loading, dispatch). Use this ONLY for drill-down into what actually happened at a hub - vw_hub_dashboard_summary already exposes the aggregated counts (inbound_vehicle_count, processed_event_count, avg_dwell_time_minutes, etc.).",
        grain: "one row per hub operational event",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:hub_id, :integer, "Hub where the event occurred."),
          col(:vehicle_id, :integer, "Vehicle involved, if any."),
          col(:trip_id, :integer, "Trip involved, if any."),
          col(:package_id, :integer, "Package involved, if any."),
          col(:event_type, :string, "One of: GATE_IN, UNLOADING_STARTED, UNLOADING_COMPLETED, SCANNED, SORTED, LOADING_STARTED, LOADING_COMPLETED, DISPATCH_READY, DEPARTED."),
          col(:dock_reference, :string, "Free-text dock label, if applicable."),
          col(:bay_reference, :string, "Free-text bay label, if applicable."),
          col(:occurred_at, :datetime, "When the event actually happened."),
          col(:created_at, :datetime, "Row creation time (when it was recorded)."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: [],
        date_columns: %w[occurred_at created_at updated_at],
        relationships: "hub_id/vehicle_id/trip_id/package_id join to hubs.id/vehicles.id/trips.id/packages.id.",
        example_questions: [ "What recent events happened at Indore hub?", "What is happening at Indore hub?" ]
      ),

      "vehicle_operation_events" => Source.new(
        name: "vehicle_operation_events", kind: :table,
        purpose: "Operational event history for vehicles (breakdowns, route deviations). Use this ONLY for drill-down - vw_fleet_dashboard_summary/vw_vehicle_dashboard already expose breakdown_count/route_deviation_count.",
        grain: "one row per vehicle operational event",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:vehicle_id, :integer, "Vehicle the event concerns."),
          col(:trip_id, :integer, "Trip during which it occurred, if any."),
          col(:event_type, :string, "One of: BREAKDOWN, BREAKDOWN_RESOLVED, ROUTE_DEVIATION, ROUTE_DEVIATION_RESOLVED."),
          col(:occurred_at, :datetime, "When the event actually happened."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: [],
        date_columns: %w[occurred_at created_at updated_at],
        relationships: "vehicle_id/trip_id join to vehicles.id/trips.id.",
        example_questions: [ "Which vehicles have breakdown events?", "Which vehicles have unresolved breakdowns?" ]
      ),

      "package_status_transitions" => Source.new(
        name: "package_status_transitions", kind: :table,
        purpose: "Append-only audit trail of package status changes. Use this ONLY for drill-down into a package's history - vw_shipment_dashboard already exposes latest_status_transition_at.",
        grain: "one row per recorded status change",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:package_id, :integer, "Package whose status changed."),
          col(:from_status, :string, "Previous status. NULL for a package's very first recorded transition."),
          col(:to_status, :string, "New status."),
          col(:occurred_at, :datetime, "When the change happened."),
          col(:location_type, :string, "Location type at the time of the change, if recorded."),
          col(:location_id, :integer, "Location id at the time of the change, if recorded."),
          col(:created_at, :datetime, "Row creation time.")
        ],
        safe_aggregations: [],
        date_columns: %w[occurred_at created_at],
        relationships: "package_id joins to packages.id.",
        example_questions: [ "What is the status history for package CC-PKG-000123?" ]
      ),

      "workforce_members" => Source.new(
        name: "workforce_members", kind: :table,
        purpose: "Raw workforce/staffing records per hub. No dedicated view exists for this yet.",
        grain: "one row per workforce member",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:identifier, :string, "Display identifier."),
          col(:name, :string, "Worker's name."),
          col(:role_type, :string, "One of: guard, warehouse_worker, loader, supervisor, driver, other_staff."),
          col(:hub_id, :integer, "Assigned hub id."),
          col(:shift, :string, "Free-text shift label, e.g. morning, evening, night."),
          col(:attendance_status, :string, "One of: present, absent, on_leave (current snapshot, not a history)."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: [],
        date_columns: %w[created_at updated_at],
        relationships: "id is referenced by vehicles.driver_id. hub_id joins to hubs.id.",
        example_questions: [ "How many drivers are present at Indore hub today?" ]
      ),

      "alerts" => Source.new(
        name: "alerts", kind: :table,
        purpose: "Raw alert records. Prefer the per-domain alert columns already on the views (open_alerts/critical_alerts on vw_hub_dashboard_summary, open_alert_count on vw_vehicle_dashboard/vw_shipment_dashboard) - use this table only when you need alert detail (severity, field, triggered_at) the views don't carry.",
        grain: "one row per alert",
        columns: [
          col(:id, :integer, "Primary key."),
          col(:alert_rule_id, :integer, "The AlertRule that produced this alert (not itself an approved source - do not query alert_rules)."),
          col(:group, :string, "Which business-entity type this alert is about: one of 'vehicles', 'hubs', 'packages', 'payments', 'workforce', or an 'events:<EntityType>' value for event-triggered alerts."),
          col(:record_id, :integer, "The id of the record in that group this alert is about - a loose reference, not a foreign key (join manually: alerts.record_id = <group_table>.id when alerts.group matches)."),
          col(:field, :string, "Which field/condition triggered the alert."),
          col(:expected_value, :string, "The condition's expected value."),
          col(:actual_value, :string, "The field's actual value when the alert fired."),
          col(:severity, :string, "One of: info, warning, critical."),
          col(:status, :string, "One of: open, acknowledged, resolved."),
          col(:triggered_at, :datetime, "When the alert fired."),
          col(:resolved_at, :datetime, "When the alert was resolved, if it has been."),
          col(:created_at, :datetime, "Row creation time."),
          col(:updated_at, :datetime, "Row last-updated time.")
        ],
        safe_aggregations: [],
        date_columns: %w[triggered_at resolved_at created_at updated_at],
        relationships: "record_id is a LOOSE reference (not a real FK) into whichever table 'group' names - e.g. group='hubs' means record_id=hubs.id. There is no 'payment_dues' or 'alert_rules' access - those are explicitly out of scope for this chatbot.",
        example_questions: [ "How many critical alerts are open?", "What alerts are open for hubs?" ]
      )
    }.freeze

    SOURCES = VIEW_SOURCES.merge(TABLE_SOURCES).freeze

    def self.fetch(source_name)
      SOURCES[source_name.to_s]
    end

    def self.approved_source_names
      SOURCES.keys
    end

    def self.view_names
      VIEW_SOURCES.keys
    end

    def self.table_names
      TABLE_SOURCES.keys
    end
  end
end
