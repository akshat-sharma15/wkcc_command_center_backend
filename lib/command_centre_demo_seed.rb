# Command Centre demo/synthetic dataset generator (Phase 3).
#
# Deliberately NOT part of db/seeds.rb / db:seed - this is a separate,
# explicitly-invoked demo dataset for Superset/dashboard testing against
# the Phase 1/2 data foundation (vehicle coordinates+mileage+fuel
# efficiency, vehicle_operation_events, hub_operations_events, orders,
# package order/delivery fields, package_status_transitions) and the
# Phase 2 SQL views. It never touches alert_rules, alerts,
# event_definitions, notifications, Integration/SlackOauthState, or the
# existing `warehouses` table/model - see CommandCentreDemoSeed.run! and
# its guarded_counts check.
#
# Deterministic: a fixed Random seed and a fixed anchor time (DEMO_NOW,
# not Time.current) mean re-running this task on any date reproduces
# exactly the same rows, as long as the run starts from the same prior
# state (see reset_demo_data!, which deletes only its own previously
# generated CC-* rows before regenerating).
#
# All heavy inserts use ActiveRecord's insert_all (bulk SQL INSERT,
# bypassing callbacks/validations) given the target scale (tens of
# thousands of rows) - this file is responsible for only ever building
# rows that already satisfy each model's real validations/enums, since
# insert_all cannot check that for us.
module CommandCentreDemoSeed
  SEED = 424_242
  DEMO_NOW = Time.zone.parse("2026-09-24 09:00:00")

  HUB_CODE_PREFIX = "CC-HUB-"
  VEHICLE_NUMBER_PREFIX = "CC-VEH-"
  WORKFORCE_ID_PREFIX = "CC-WF-"
  ORDER_NUMBER_PREFIX = "CC-ORD-"
  PACKAGE_ID_PREFIX = "CC-PKG-"

  HUB_TARGET = 47
  WORKFORCE_TARGET = 700
  VEHICLE_TARGET = 300
  TRIP_TARGET = 3000
  ORDER_TARGET = 7500
  STANDALONE_PACKAGE_TARGET = 1500

  # [city, latitude, longitude] - approximate city-centre coordinates for
  # synthetic demo geography. Not tied to any real facility.
  CITIES = [
    [ "Delhi", 28.6139, 77.2090 ], [ "Jaipur", 26.9124, 75.7873 ], [ "Chandigarh", 30.7333, 76.7794 ],
    [ "Lucknow", 26.8467, 80.9462 ], [ "Kanpur", 26.4499, 80.3319 ], [ "Ludhiana", 30.9010, 75.8573 ],
    [ "Dehradun", 30.3165, 78.0322 ], [ "Agra", 27.1767, 78.0081 ], [ "Amritsar", 31.6340, 74.8723 ],
    [ "Meerut", 28.9845, 77.7064 ],
    [ "Mumbai", 19.0760, 72.8777 ], [ "Pune", 18.5204, 73.8567 ], [ "Ahmedabad", 23.0225, 72.5714 ],
    [ "Surat", 21.1702, 72.8311 ], [ "Vadodara", 22.3072, 73.1812 ], [ "Indore", 22.7196, 75.8577 ],
    [ "Rajkot", 22.3039, 70.8022 ], [ "Nashik", 19.9975, 73.7898 ],
    [ "Bhopal", 23.2599, 77.4126 ], [ "Nagpur", 21.1458, 79.0882 ], [ "Raipur", 21.2514, 81.6296 ],
    [ "Jabalpur", 23.1815, 79.9864 ], [ "Kota", 25.2138, 75.8648 ], [ "Gwalior", 26.2183, 78.1828 ],
    [ "Bengaluru", 12.9716, 77.5946 ], [ "Hyderabad", 17.3850, 78.4867 ], [ "Chennai", 13.0827, 80.2707 ],
    [ "Kochi", 9.9312, 76.2673 ], [ "Coimbatore", 11.0168, 76.9558 ], [ "Mysuru", 12.2958, 76.6394 ],
    [ "Vijayawada", 16.5062, 80.6480 ], [ "Visakhapatnam", 17.6868, 83.2185 ], [ "Madurai", 9.9252, 78.1198 ],
    [ "Thiruvananthapuram", 8.5241, 76.9366 ], [ "Salem", 11.6643, 78.1460 ], [ "Guntur", 16.3067, 80.4365 ],
    [ "Kolkata", 22.5726, 88.3639 ], [ "Bhubaneswar", 20.2961, 85.8245 ], [ "Patna", 25.5941, 85.1376 ],
    [ "Ranchi", 23.3441, 85.3096 ], [ "Guwahati", 26.1445, 91.7362 ], [ "Siliguri", 26.7271, 88.3953 ],
    [ "Jamshedpur", 22.8046, 86.2029 ], [ "Durgapur", 23.5204, 87.3119 ],
    [ "Varanasi", 25.3176, 82.9739 ], [ "Faridabad", 28.4089, 77.3178 ], [ "Jodhpur", 26.2389, 73.0243 ]
  ].freeze

  VEHICLE_TYPES = %w[truck mini_truck trailer van].freeze
  VENDORS = [
    "Tata Motors Fleet", "Ashok Leyland Leasing", "Mahindra Logistics",
    "Independent Owner", "VRL Logistics Partner", "Regional Fleet Co-op"
  ].freeze
  SHIFTS = %w[morning evening night].freeze
  PRIORITIES = %w[low standard high urgent].freeze
  FIRST_NAMES = %w[
    Amit Priya Rahul Sunita Vikram Neha Sanjay Pooja Rajesh Anita
    Manoj Kavita Arjun Deepa Suresh Meena Ravi Divya Ashok Rekha
    Vijay Sneha Anil Geeta Kiran Shalini Naveen Preeti Dinesh Radha
  ].freeze
  LAST_NAMES = %w[
    Sharma Verma Patel Singh Gupta Reddy Nair Iyer Joshi Mehta
    Kumar Yadav Choudhary Rao Pillai Desai Malhotra Kapoor Bose Menon
  ].freeze

  class << self
    def run!
      @rng = Random.new(SEED)

      before = guarded_counts
      reset_demo_data!

      hubs = seed_hubs!
      congested_hub_ids = pick_congested_hubs(hubs)
      drivers_by_hub = seed_workforce!(hubs)
      vehicles = seed_vehicles!(hubs, drivers_by_hub)
      trips = seed_trips!(hubs, vehicles)
      update_vehicle_locations_for_active_trips!(vehicles, trips, hubs)
      orders = seed_orders!(hubs, trips)
      packages = seed_packages!(hubs, orders, trips)
      reconcile_order_package_counts!
      seed_package_status_transitions!(packages)
      seed_hub_operations_events!(trips, packages, congested_hub_ids)
      seed_vehicle_operations_events!(vehicles, trips)

      after = guarded_counts
      report(before, after, hubs, vehicles, trips, orders, packages, congested_hub_ids)
    end

    private

    # ---------------------------------------------------------------
    # Safety: alert/event/notification/Slack/warehouse tables
    # ---------------------------------------------------------------
    def guarded_counts
      {
        alert_rules: AlertRule.count,
        event_definitions: EventDefinition.count,
        alerts: Alert.count,
        notifications: Notification.count,
        warehouses: Warehouse.count
      }
    end

    # Deletes only rows this task itself previously created (identified by
    # the CC- prefixes), in child-to-parent order, so the task is safely
    # re-runnable without touching Phase 1 seed data (HUB-IND, VH-1000,
    # ...) or the alert/event/notification/warehouse tables.
    def reset_demo_data!
      hub_ids = Hub.where("code LIKE ?", "#{HUB_CODE_PREFIX}%").pluck(:id)
      vehicle_ids = Vehicle.where("number LIKE ?", "#{VEHICLE_NUMBER_PREFIX}%").pluck(:id)
      return if hub_ids.empty? && vehicle_ids.empty?

      trip_ids = Trip.where(vehicle_id: vehicle_ids)
                      .or(Trip.where(origin_hub_id: hub_ids))
                      .or(Trip.where(destination_hub_id: hub_ids))
                      .pluck(:id)
      order_ids = Order.where("order_number LIKE ?", "#{ORDER_NUMBER_PREFIX}%").pluck(:id)
      package_ids = Package.where("identifier LIKE ?", "#{PACKAGE_ID_PREFIX}%").pluck(:id)

      PackageStatusTransition.where(package_id: package_ids).delete_all
      HubOperationsEvent.where(hub_id: hub_ids).delete_all
      VehicleOperationEvent.where(vehicle_id: vehicle_ids).delete_all
      Package.where(id: package_ids).delete_all
      Order.where(id: order_ids).delete_all
      Trip.where(id: trip_ids).delete_all
      Vehicle.where(id: vehicle_ids).delete_all
      WorkforceMember.where("identifier LIKE ?", "#{WORKFORCE_ID_PREFIX}%").delete_all
      Hub.where(id: hub_ids).delete_all
    end

    # ---------------------------------------------------------------
    # Helpers
    # ---------------------------------------------------------------
    def bulk_insert!(model, rows, batch_size: 2000)
      ids = []
      rows.each_slice(batch_size) do |slice|
        result = model.insert_all(slice, returning: [ :id ])
        ids.concat(result.rows.flatten)
      end
      rows.each_with_index { |row, i| row[:id] = ids[i] }
      rows
    end

    def weighted_choice(weights)
      total = weights.values.sum
      r = @rng.rand(total)
      cumulative = 0
      weights.each do |key, weight|
        cumulative += weight
        return key if r < cumulative
      end
      weights.keys.last
    end

    def haversine_km(lat1, lng1, lat2, lng2)
      rad = Math::PI / 180
      dlat = (lat2 - lat1) * rad
      dlng = (lng2 - lng1) * rad
      a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * (Math.sin(dlng / 2)**2))
      2 * 6371 * Math.asin(Math.sqrt(a))
    end

    def jitter(base, max_delta)
      base + ((@rng.rand - 0.5) * 2 * max_delta)
    end

    def synthetic_name
      "#{FIRST_NAMES.sample(random: @rng)} #{LAST_NAMES.sample(random: @rng)}"
    end

    def hub_weight(tier)
      { large: 5, medium: 2, small: 1 }.fetch(tier)
    end

    # ---------------------------------------------------------------
    # Step: Hubs
    # ---------------------------------------------------------------
    def seed_hubs!
      tiers = CITIES.map { weighted_choice(large: 15, medium: 55, small: 30) }
      large_indexes = tiers.each_index.select { |i| tiers[i] == :large }
      congested_seed_indexes = large_indexes.sample(4, random: @rng)

      rows = CITIES.each_with_index.map do |(name, lat, lng), idx|
        tier = tiers[idx]
        congested = congested_seed_indexes.include?(idx)

        capacity = case tier
        when :large then @rng.rand(700..1200)
        when :medium then @rng.rand(350..700)
        else @rng.rand(100..350)
        end
        parking_capacity = case tier
        when :large then @rng.rand(60..100)
        when :medium then @rng.rand(30..60)
        else @rng.rand(10..30)
        end
        available_parking = congested ? @rng.rand(0..(parking_capacity * 0.15).floor) : @rng.rand(0..parking_capacity)
        operational_status = if congested
                                "degraded"
        else
                                weighted_choice(active: 94, degraded: 6)
        end

        {
          code: format("%s%03d", HUB_CODE_PREFIX, idx + 1),
          name: "#{name} Command Centre Hub",
          location: "#{name}, India",
          capacity: capacity,
          parking_capacity: parking_capacity,
          available_parking: available_parking,
          operational_status: operational_status.to_s,
          created_at: DEMO_NOW,
          updated_at: DEMO_NOW,
          _tier: tier,
          _lat: lat,
          _lng: lng,
          _congested: congested
        }
      end

      db_rows = rows.map { |r| r.reject { |k, _| k.to_s.start_with?("_") } }
      bulk_insert!(Hub, db_rows)
      rows.each_with_index { |r, i| r[:id] = db_rows[i][:id] }
      rows
    end

    def pick_congested_hubs(hubs)
      hubs.select { |h| h[:_congested] }.map { |h| h[:id] }
    end

    def weighted_hub_pool(hubs)
      @weighted_hub_pool ||= hubs.flat_map { |h| [ h ] * hub_weight(h[:_tier]) }
    end

    def distinct_hub_pair(hubs)
      pool = weighted_hub_pool(hubs)
      origin = pool.sample(random: @rng)
      destination = nil
      loop do
        destination = pool.sample(random: @rng)
        break if destination[:code] != origin[:code]
      end
      [ origin, destination ]
    end

    # ---------------------------------------------------------------
    # Step: Workforce
    # ---------------------------------------------------------------
    def seed_workforce!(hubs)
      pool = weighted_hub_pool(hubs)
      role_weights = { driver: 40, warehouse_worker: 20, loader: 20, guard: 10, supervisor: 5, other_staff: 5 }
      attendance_weights = { present: 85, absent: 8, on_leave: 7 }

      rows = (1..WORKFORCE_TARGET).map do |idx|
        hub = pool.sample(random: @rng)
        {
          identifier: format("%s%05d", WORKFORCE_ID_PREFIX, idx),
          name: synthetic_name,
          role_type: weighted_choice(role_weights).to_s,
          hub_id: hub[:id],
          shift: SHIFTS.sample(random: @rng),
          attendance_status: weighted_choice(attendance_weights).to_s,
          created_at: DEMO_NOW,
          updated_at: DEMO_NOW
        }
      end

      bulk_insert!(WorkforceMember, rows)
      WorkforceMember.where("identifier LIKE ?", "#{WORKFORCE_ID_PREFIX}%")
                      .where(role_type: "driver")
                      .pluck(:hub_id, :id)
                      .group_by(&:first)
                      .transform_values { |pairs| pairs.map(&:last) }
    end

    # ---------------------------------------------------------------
    # Step: Vehicles
    # ---------------------------------------------------------------
    def seed_vehicles!(hubs, drivers_by_hub)
      pool = weighted_hub_pool(hubs)
      status_weights = { active: 80, maintenance: 14, out_of_service: 6 }
      capacities = [ 500, 1000, 2000, 3500, 5000, 8000, 10_000 ]

      rows = (1..VEHICLE_TARGET).map do |idx|
        hub = pool.sample(random: @rng)
        vtype = VEHICLE_TYPES.sample(random: @rng)
        fuel_eff = case vtype
        when "truck" then @rng.rand(3.0..6.0)
        when "trailer" then @rng.rand(2.5..4.5)
        when "mini_truck" then @rng.rand(6.0..10.0)
        else @rng.rand(8.0..14.0)
        end
        driver_id = drivers_by_hub[hub[:id]]&.sample(random: @rng)
        lat = jitter(hub[:_lat], 0.12)
        lng = jitter(hub[:_lng], 0.12)

        {
          number: format("%s%04d", VEHICLE_NUMBER_PREFIX, idx),
          vehicle_type: vtype,
          status: weighted_choice(status_weights).to_s,
          capacity: capacities.sample(random: @rng),
          vendor: VENDORS.sample(random: @rng),
          current_location: hub[:location],
          hub_id: hub[:id],
          driver_id: driver_id,
          last_known_latitude: lat.round(6),
          last_known_longitude: lng.round(6),
          last_location_at: DEMO_NOW - @rng.rand(0..180).minutes,
          mileage_km: @rng.rand(5_000..250_000).to_f.round(2),
          fuel_efficiency_kmpl: fuel_eff.round(2),
          created_at: DEMO_NOW,
          updated_at: DEMO_NOW,
          _hub: hub
        }
      end

      db_rows = rows.map { |r| r.reject { |k, _| k.to_s.start_with?("_") } }
      bulk_insert!(Vehicle, db_rows)
      rows.each_with_index { |r, i| r[:id] = db_rows[i][:id] }
      rows
    end

    # ---------------------------------------------------------------
    # Step: Trips
    # ---------------------------------------------------------------
    def seed_trips!(hubs, vehicles)
      status_weights = { completed: 45, in_transit: 15, scheduled: 20, delayed: 12, cancelled: 8 }

      rows = (1..TRIP_TARGET).map do
        vehicle = vehicles.sample(random: @rng)
        origin, destination = distinct_hub_pair(hubs)
        status = weighted_choice(status_weights).to_s
        distance_km = haversine_km(origin[:_lat], origin[:_lng], destination[:_lat], destination[:_lng])
        duration_hours = (distance_km / 45.0) + @rng.rand(0.5..2.5)

        departure_at, expected_arrival_at, actual_arrival_at = trip_timestamps(status, duration_hours)

        {
          vehicle_id: vehicle[:id],
          origin_hub_id: origin[:id],
          destination_hub_id: destination[:id],
          departure_at: departure_at,
          expected_arrival_at: expected_arrival_at,
          actual_arrival_at: actual_arrival_at,
          status: status,
          route_info: "#{origin[:location]} -> #{destination[:location]}",
          created_at: DEMO_NOW,
          updated_at: DEMO_NOW
        }
      end

      bulk_insert!(Trip, rows)
      rows
    end

    def trip_timestamps(status, duration_hours)
      case status
      when "scheduled"
        departure_at = DEMO_NOW + @rng.rand(1..72).hours + @rng.rand(0..59).minutes
        [ departure_at, departure_at + duration_hours.hours, nil ]
      when "in_transit"
        departure_at = DEMO_NOW - @rng.rand(1..36).hours
        [ departure_at, departure_at + duration_hours.hours, nil ]
      when "completed"
        departure_at = DEMO_NOW - @rng.rand(1..30).days - @rng.rand(0..23).hours
        expected = departure_at + duration_hours.hours
        [ departure_at, expected, expected + @rng.rand(-90..60).minutes ]
      when "delayed"
        departure_at = DEMO_NOW - @rng.rand(1..30).days - @rng.rand(0..23).hours
        expected = departure_at + duration_hours.hours
        actual = @rng.rand < 0.7 ? expected + @rng.rand(120..600).minutes : nil
        [ departure_at, expected, actual ]
      when "cancelled"
        departure_at = DEMO_NOW - @rng.rand(0..30).days
        [ departure_at, departure_at + duration_hours.hours, nil ]
      end
    end

    def update_vehicle_locations_for_active_trips!(vehicles, trips, hubs)
      hubs_by_id = hubs.index_by { |h| h[:id] }
      in_transit_by_vehicle = trips.select { |t| t[:status] == "in_transit" }.group_by { |t| t[:vehicle_id] }

      vehicles.each do |v|
        trip = in_transit_by_vehicle[v[:id]]&.first
        next unless trip

        origin = hubs_by_id[trip[:origin_hub_id]]
        destination = hubs_by_id[trip[:destination_hub_id]]
        fraction = @rng.rand(0.1..0.9)
        lat = (origin[:_lat] + ((destination[:_lat] - origin[:_lat]) * fraction)).round(6)
        lng = (origin[:_lng] + ((destination[:_lng] - origin[:_lng]) * fraction)).round(6)
        pinged_at = trip[:departure_at] + (fraction * (DEMO_NOW - trip[:departure_at]))

        Vehicle.where(id: v[:id]).update_all(
          last_known_latitude: lat, last_known_longitude: lng, last_location_at: pinged_at
        )
      end
    end

    # ---------------------------------------------------------------
    # Step: Orders
    # ---------------------------------------------------------------
    def seed_orders!(hubs, trips)
      status_weights = { pending: 15, processing: 15, in_transit: 20, delivered: 40, cancelled: 10 }
      package_count_weights = { 1 => 50, 2 => 25, 3 => 15, 4 => 10 }
      trip_pairs = trips.map { |t| [ t[:origin_hub_id], t[:destination_hub_id] ] }

      rows = (1..ORDER_TARGET).map do |idx|
        origin_id, destination_id =
          if @rng.rand < 0.7 && trip_pairs.any?
            trip_pairs.sample(random: @rng)
          else
            o, d = distinct_hub_pair(hubs)
            [ o[:id], d[:id] ]
          end

        status = weighted_choice(status_weights).to_s
        planned_packages = weighted_choice(package_count_weights)
        created_at = DEMO_NOW - @rng.rand(1..35).days
        promised = created_at + @rng.rand(2..7).days
        delivered_at = nil
        if status == "delivered"
          delivered_at = [ promised + @rng.rand(-24..48).hours, DEMO_NOW ].min
        end

        {
          order_number: format("%s%06d", ORDER_NUMBER_PREFIX, idx),
          customer_reference: format("CUST-%05d", @rng.rand(1..3000)),
          status: status,
          priority: PRIORITIES.sample(random: @rng),
          origin_hub_id: origin_id,
          destination_hub_id: destination_id,
          package_count: planned_packages,
          total_weight: (planned_packages * @rng.rand(2.0..80.0)).round(2),
          promised_delivery_at: promised,
          delivered_at: delivered_at,
          created_at: created_at,
          updated_at: created_at,
          _planned_packages: planned_packages
        }
      end

      db_rows = rows.map { |r| r.reject { |k, _| k.to_s.start_with?("_") } }
      bulk_insert!(Order, db_rows)
      rows.each_with_index { |r, i| r[:id] = db_rows[i][:id] }
      rows
    end

    # ---------------------------------------------------------------
    # Step: Packages
    # ---------------------------------------------------------------
    def seed_packages!(hubs, orders, trips)
      hubs_by_id = hubs.index_by { |h| h[:id] }
      trips_by_pair = trips.group_by { |t| [ t[:origin_hub_id], t[:destination_hub_id] ] }
      status_weights = { delivered: 44, received: 21, in_transit: 17, pending: 8, damaged: 5, short: 5 }

      counter = 0
      rows = []

      orders.each do |order|
        order[:_planned_packages].times do
          counter += 1
          status = order[:status] == "cancelled" ? "pending" : weighted_choice(status_weights).to_s
          candidate_trips = trips_by_pair[[ order[:origin_hub_id], order[:destination_hub_id] ]]
          trip = status == "pending" ? nil : candidate_trips&.sample(random: @rng)

          location_hub_id =
            if trip && %w[received delivered damaged short].include?(status)
              trip[:destination_hub_id]
            else
              order[:origin_hub_id]
            end

          expected_quantity = @rng.rand(1..40)
          received_quantity, damaged_quantity, short_quantity = quantities_for(status, expected_quantity)

          package_created_at = order[:created_at] + @rng.rand(0..2).hours
          delivered_at = nil
          if status == "delivered"
            delivered_at = [ order[:promised_delivery_at] + @rng.rand(-1440..2880).minutes, DEMO_NOW ].min
            delivered_at = [ delivered_at, package_created_at + 1.hour ].max
          end

          rows << {
            identifier: format("%s%06d", PACKAGE_ID_PREFIX, counter),
            order_id: order[:id],
            trip_id: trip&.dig(:id),
            location_type: "Hub",
            location_id: location_hub_id,
            expected_quantity: expected_quantity,
            received_quantity: received_quantity,
            damaged_quantity: damaged_quantity,
            short_quantity: short_quantity,
            status: status,
            promised_delivery_at: nil,
            delivered_at: delivered_at,
            allow_alerts: false,
            alertable_fields: [],
            created_at: package_created_at,
            updated_at: package_created_at,
            _origin_hub_id: order[:origin_hub_id]
          }
        end
      end

      STANDALONE_PACKAGE_TARGET.times do
        counter += 1
        hub = weighted_hub_pool(hubs).sample(random: @rng)
        status = weighted_choice(status_weights).to_s
        expected_quantity = @rng.rand(1..40)
        received_quantity, damaged_quantity, short_quantity = quantities_for(status, expected_quantity)
        created_at = DEMO_NOW - @rng.rand(1..35).days
        promised = created_at + @rng.rand(2..7).days
        delivered_at = status == "delivered" ? [ promised + @rng.rand(-1440..2880).minutes, DEMO_NOW ].min : nil

        rows << {
          identifier: format("%s%06d", PACKAGE_ID_PREFIX, counter),
          order_id: nil,
          trip_id: nil,
          location_type: "Hub",
          location_id: hub[:id],
          expected_quantity: expected_quantity,
          received_quantity: received_quantity,
          damaged_quantity: damaged_quantity,
          short_quantity: short_quantity,
          status: status,
          promised_delivery_at: promised,
          delivered_at: delivered_at,
          allow_alerts: false,
          alertable_fields: [],
          created_at: created_at,
          updated_at: created_at,
          _origin_hub_id: hub[:id]
        }
      end

      db_rows = rows.map { |r| r.reject { |k, _| k.to_s.start_with?("_") } }
      bulk_insert!(Package, db_rows)
      rows.each_with_index { |r, i| r[:id] = db_rows[i][:id] }
      rows
    end

    def quantities_for(status, expected_quantity)
      case status
      when "damaged"
        damaged = @rng.rand(1..expected_quantity)
        [ expected_quantity - damaged, damaged, 0 ]
      when "short"
        short = @rng.rand(1..expected_quantity)
        [ expected_quantity - short, 0, short ]
      else
        [ expected_quantity, 0, 0 ]
      end
    end

    def reconcile_order_package_counts!
      OperationsRecord.connection.execute(<<~SQL.squish)
        UPDATE orders o
        SET package_count = sub.cnt
        FROM (
          SELECT order_id, COUNT(*) AS cnt FROM packages WHERE order_id IS NOT NULL GROUP BY order_id
        ) sub
        WHERE o.id = sub.order_id AND o.order_number LIKE '#{ORDER_NUMBER_PREFIX}%'
      SQL
    end

    # ---------------------------------------------------------------
    # Step: Package status transitions
    # ---------------------------------------------------------------
    def status_chain_for(final_status)
      case final_status
      when "pending" then %w[pending]
      when "in_transit" then %w[pending in_transit]
      when "received" then %w[pending in_transit received]
      when "delivered" then %w[pending in_transit received delivered]
      when "damaged" then %w[pending in_transit received damaged]
      when "short" then %w[pending in_transit received short]
      end
    end

    def seed_package_status_transitions!(packages)
      rows = []

      packages.each do |pkg|
        chain = status_chain_for(pkg[:status])
        next if chain.size <= 1

        start_t = pkg[:created_at]
        end_t = pkg[:delivered_at] || DEMO_NOW
        end_t = start_t + 1.hour if end_t <= start_t
        steps = chain.size - 1
        gap = (end_t - start_t) / steps

        (0...steps).each do |i|
          occurred_at = start_t + (gap * (i + 1))
          rows << {
            package_id: pkg[:id],
            from_status: chain[i],
            to_status: chain[i + 1],
            occurred_at: occurred_at,
            location_type: "Hub",
            location_id: i.zero? ? pkg[:_origin_hub_id] : pkg[:location_id],
            created_at: occurred_at
          }
        end
      end

      bulk_insert!(PackageStatusTransition, rows)
    end

    # ---------------------------------------------------------------
    # Step: Hub operations events
    # ---------------------------------------------------------------
    def hub_event_row(hub_id, vehicle_id, trip_id, package_id, event_type, occurred_at)
      dock = %w[GATE_IN LOADING_STARTED LOADING_COMPLETED DISPATCH_READY DEPARTED].include?(event_type) ? "DOCK-#{(occurred_at.to_i % 8) + 1}" : nil
      bay = %w[UNLOADING_STARTED UNLOADING_COMPLETED SORTED].include?(event_type) ? "BAY-#{(occurred_at.to_i % 6) + 1}" : nil

      {
        hub_id: hub_id,
        vehicle_id: vehicle_id,
        trip_id: trip_id,
        package_id: package_id,
        event_type: event_type,
        dock_reference: dock,
        bay_reference: bay,
        occurred_at: occurred_at,
        metadata: nil,
        created_at: DEMO_NOW,
        updated_at: DEMO_NOW
      }
    end

    def seed_hub_operations_events!(trips, packages, congested_hub_ids)
      packages_by_trip = packages.group_by { |p| p[:trip_id] }
      rows = []

      trips.each do |trip|
        next if %w[scheduled cancelled].include?(trip[:status])

        t = trip[:departure_at] - @rng.rand(40..120).minutes
        %w[GATE_IN LOADING_STARTED LOADING_COMPLETED DISPATCH_READY DEPARTED].each do |etype|
          rows << hub_event_row(trip[:origin_hub_id], trip[:vehicle_id], trip[:id], nil, etype, t)
          t += @rng.rand(5..25).minutes
        end

        next unless trip[:actual_arrival_at]

        congested = congested_hub_ids.include?(trip[:destination_hub_id])
        sequence = (congested && @rng.rand < 0.55) ? %w[GATE_IN UNLOADING_STARTED] : %w[GATE_IN UNLOADING_STARTED UNLOADING_COMPLETED]
        t2 = trip[:actual_arrival_at]
        sequence.each do |etype|
          rows << hub_event_row(trip[:destination_hub_id], trip[:vehicle_id], trip[:id], nil, etype, t2)
          t2 += @rng.rand(10..40).minutes
        end

        next unless sequence.last == "UNLOADING_COMPLETED"

        trip_packages = packages_by_trip[trip[:id]] || []
        trip_packages.first(5).each do |pkg|
          rows << hub_event_row(trip[:destination_hub_id], trip[:vehicle_id], trip[:id], pkg[:id], "SCANNED", t2)
          t2 += @rng.rand(1..4).minutes
        end
        rows << hub_event_row(trip[:destination_hub_id], trip[:vehicle_id], trip[:id], nil, "SORTED", t2 + @rng.rand(5..15).minutes)
      end

      bulk_insert!(HubOperationsEvent, rows)
    end

    # ---------------------------------------------------------------
    # Step: Vehicle operations events
    # ---------------------------------------------------------------
    def vehicle_event_row(vehicle_id, trip_id, event_type, occurred_at, reason)
      {
        vehicle_id: vehicle_id,
        trip_id: trip_id,
        event_type: event_type,
        occurred_at: occurred_at,
        metadata: { "reason" => reason }.to_json,
        created_at: DEMO_NOW,
        updated_at: DEMO_NOW
      }
    end

    def seed_vehicle_operations_events!(vehicles, trips)
      trips_by_vehicle = trips.group_by { |t| t[:vehicle_id] }
      incident_weights = { 0 => 50, 1 => 30, 2 => 12, 3 => 8 }
      breakdown_reasons = [ "Engine overheating", "Tyre puncture", "Brake fault", "Electrical failure" ]
      deviation_reasons = [ "Road closure detour", "Traffic diversion", "Driver rerouted for fuel stop" ]
      rows = []

      vehicles.each do |v|
        n = weighted_choice(incident_weights)
        next if n.zero?

        my_trips = (trips_by_vehicle[v[:id]] || []).select { |t| t[:departure_at].present? }
        next if my_trips.empty?

        n.times do
          trip = my_trips.sample(random: @rng)
          endpoint = trip[:actual_arrival_at] || trip[:expected_arrival_at]
          duration_seconds = endpoint - trip[:departure_at]
          next if duration_seconds <= 0

          occurred_at = trip[:departure_at] + (@rng.rand(0.1..0.8) * duration_seconds)
          is_breakdown = @rng.rand < 0.5
          kind = is_breakdown ? "BREAKDOWN" : "ROUTE_DEVIATION"
          reason = (is_breakdown ? breakdown_reasons : deviation_reasons).sample(random: @rng)

          rows << vehicle_event_row(v[:id], trip[:id], kind, occurred_at, reason)

          next unless @rng.rand < 0.75

          resolved_at = occurred_at + @rng.rand(20..180).minutes
          rows << vehicle_event_row(v[:id], trip[:id], "#{kind}_RESOLVED", resolved_at, "Resolved")
        end
      end

      bulk_insert!(VehicleOperationEvent, rows)
    end

    # ---------------------------------------------------------------
    # Reporting
    # ---------------------------------------------------------------
    def report(before, after, hubs, vehicles, trips, orders, packages, congested_hub_ids)
      puts "\n=== Command Centre demo seed complete ==="
      puts "Hubs: #{Hub.where('code LIKE ?', "#{HUB_CODE_PREFIX}%").count}"
      puts "  by tier: #{hubs.group_by { |h| h[:_tier] }.transform_values(&:count)}"
      puts "  congested hub ids: #{congested_hub_ids}"
      puts "Workforce members: #{WorkforceMember.where('identifier LIKE ?', "#{WORKFORCE_ID_PREFIX}%").count}"
      puts "Vehicles: #{Vehicle.where('number LIKE ?', "#{VEHICLE_NUMBER_PREFIX}%").count}"
      puts "  by status: #{vehicles.group_by { |v| v[:status] }.transform_values(&:count)}"
      puts "Trips: #{trips.size}"
      puts "  by status: #{trips.group_by { |t| t[:status] }.transform_values(&:count)}"
      puts "Orders: #{orders.size}"
      puts "  by status: #{orders.group_by { |o| o[:status] }.transform_values(&:count)}"
      puts "Packages: #{packages.size}"
      puts "  by status: #{packages.group_by { |p| p[:status] }.transform_values(&:count)}"
      puts "Package status transitions: #{PackageStatusTransition.where(package_id: packages.map { |p| p[:id] }).count}"
      puts "Guarded counts before: #{before}"
      puts "Guarded counts after:  #{after}"
      puts "Guarded counts unchanged: #{before == after}"
    end
  end
end
