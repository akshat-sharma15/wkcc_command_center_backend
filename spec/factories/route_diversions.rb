FactoryBot.define do
  factory :route_diversion do
    trip { association :trip, status: "in_transit" }
    vehicle { trip.vehicle }
    reason { "Road closure" }
    status { "active" }
    diverted_at { Time.current }
    original_path { [ { "name" => "Indore", "lat" => 22.7196, "lng" => 75.8577 }, { "name" => "Ujjain", "lat" => 23.1765, "lng" => 75.7885 }, { "name" => "Ratlam", "lat" => 23.3315, "lng" => 75.0367 } ] }
    diverted_path { [ { "name" => "Indore", "lat" => 22.7196, "lng" => 75.8577 }, { "name" => "Dhar", "lat" => 22.6013, "lng" => 75.3025 }, { "name" => "Ratlam", "lat" => 23.3315, "lng" => 75.0367 } ] }
  end
end
