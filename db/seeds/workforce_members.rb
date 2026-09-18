puts "Seeding workforce members..."

hubs = Hub.all.index_by(&:code)
role_weights = {
  "guard" => 2, "warehouse_worker" => 4, "loader" => 4,
  "supervisor" => 1, "driver" => 3, "other_staff" => 1
}
shifts = %w[morning evening night]
attendance_weights = { "present" => 8, "absent" => 1, "on_leave" => 1 }

seq = 1
hubs.each_value do |hub|
  role_weights.each do |role, count|
    count.times do
      identifier = format("WF-%04d", seq)
      seq += 1

      next if WorkforceMember.exists?(identifier: identifier)

      WorkforceMember.create!(
        identifier: identifier,
        name: Faker::Name.name,
        role_type: role,
        hub: hub,
        shift: shifts.sample,
        attendance_status: attendance_weights.flat_map { |status, w| [status] * w }.sample
      )
    end
  end
end
