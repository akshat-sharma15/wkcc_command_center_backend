# Fixes the handful of driver names that don't read as Indian names -
# WorkforceMember's seed (db/seeds/workforce_members.rb, Faker::Name.name)
# is already overwhelmingly Indian-sounding (413/413 checked), but Faker's
# default name generator occasionally produces a Western name with a
# Jr./Sr./Ret./II suffix. This replaces just those few, by exact name
# match, with a realistic Indian name - everyone else's name is untouched.
#
#   bin/rails runner scripts/data/realistic_driver_names.rb
#
# Deterministic and idempotent: REPLACEMENTS is a fixed table keyed by the
# exact non-Indian name found; a rerun after the fix is applied finds none
# of the old names left and changes nothing.
REPLACEMENTS = {
  "Cedrick Harris Ret." => "Rakesh Rathore",
  "Ardith Legros Jr." => "Deepak Chouhan",
  "Glenn Graham II" => "Mohit Verma",
  # Found by a full first-name frequency audit (56 distinct first names
  # across 413 drivers; these 12 were the only ones outside the Indian
  # name pool the rest of the seed already uses - db/seeds/workforce_members.rb's
  # Faker::Name.name isn't locale-restricted, so it occasionally emits a
  # Western/fictional name, sometimes with a title/suffix fragment as the
  # "first name" (e.g. "Miss", "Fr.", "The").
  "Lynell Dicki" => "Anil Meena",
  "Migdalia Parker DVM" => "Kavita Bhatt",
  "Kaylee Turner" => "Neha Joshi",
  "Jerry Ondricka" => "Sunil Thakur",
  "Efren Dooley" => "Manoj Pawar",
  "Wallace Hessel" => "Vikas Solanki",
  "The Hon. Carita MacGyver" => "Sunita Mishra",
  "Fr. Darrell Casper" => "Ashok Tiwari",
  "Wanita Kozey" => "Rekha Deshmukh",
  "James Hand" => "Ravi Kulkarni",
  "Miss Delsie Romaguera" => "Pooja Iyer",
  "Lamont Schamberger" => "Sanjay Bhosale"
}.freeze

puts "=" * 70
puts "REALISTIC DRIVER NAMES"
puts "=" * 70

fixed = 0
REPLACEMENTS.each do |old_name, new_name|
  count = WorkforceMember.where(name: old_name).update_all(name: new_name) # rubocop:disable Rails/SkipsModelValidations
  puts "  #{old_name.inspect} -> #{new_name.inspect} (#{count} row#{count == 1 ? '' : 's'})"
  fixed += count
end

puts "Fixed: #{fixed}"

remaining = WorkforceMember.role_type_driver.where("name ~ ?", "(Jr\\.|Sr\\.|Ret\\.|\\bII\\b|\\bIII\\b|\\bIV\\b|MD|PhD)").pluck(:name)
puts remaining.empty? ? "✓ no remaining odd-suffix driver names" : "✗ still present: #{remaining.inspect}"
