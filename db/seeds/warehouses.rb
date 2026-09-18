puts "Seeding warehouses..."

WAREHOUSES = [
  { name: "Indore Central Warehouse", code: "WH-IND-1", location: "Indore, MP", capacity: 10_000, status: "active" },
  { name: "Jaipur Overflow Warehouse", code: "WH-JAI-1", location: "Jaipur, RJ", capacity: 4_000, status: "active" },
  { name: "Ahmedabad Bonded Warehouse", code: "WH-AMD-1", location: "Ahmedabad, GJ", capacity: 12_000, status: "active" },
  { name: "Bhopal Cold Storage", code: "WH-BPL-1", location: "Bhopal, MP", capacity: 1_500, status: "inactive" }
].freeze

WAREHOUSES.each do |attrs|
  Warehouse.find_or_create_by!(code: attrs[:code]) { |w| w.assign_attributes(attrs) }
end
