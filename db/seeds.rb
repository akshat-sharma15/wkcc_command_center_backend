# Realistic (non-uniform) development seed data, in dependency order.
# Run via: bin/rails db:seed (or ./scripts/init_db.sh, which runs it after migrating).

require_relative "seeds/hubs"
require_relative "seeds/warehouses"
require_relative "seeds/workforce_members"
require_relative "seeds/vehicles"
require_relative "seeds/trips"
require_relative "seeds/packages"
require_relative "seeds/payment_dues"
