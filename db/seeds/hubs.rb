puts "Seeding hubs..."

HUBS = [
  { name: "Indore Regional Hub", code: "HUB-IND", location: "Indore, MP", capacity: 500, parking_capacity: 40, available_parking: 12, operational_status: "active" },
  { name: "Jaipur Distribution Hub", code: "HUB-JAI", location: "Jaipur, RJ", capacity: 350, parking_capacity: 25, available_parking: 25, operational_status: "active" },
  { name: "Ratlam Transit Point", code: "HUB-RTM", location: "Ratlam, MP", capacity: 120, parking_capacity: 10, available_parking: 2, operational_status: "degraded" },
  { name: "Ahmedabad Central Hub", code: "HUB-AMD", location: "Ahmedabad, GJ", capacity: 600, parking_capacity: 50, available_parking: 31, operational_status: "active" },
  { name: "Bhopal North Hub", code: "HUB-BPL", location: "Bhopal, MP", capacity: 200, parking_capacity: 15, available_parking: 0, operational_status: "active" }
].freeze

HUBS.each do |attrs|
  Hub.find_or_create_by!(code: attrs[:code]) do |h|
    h.assign_attributes(attrs)
    h.allow_alerts = true
    h.alertable_fields = %w[operational_status capacity parking_capacity available_parking]
  end
end
