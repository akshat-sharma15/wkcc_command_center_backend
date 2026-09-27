# Shipment/Package/Delivery dashboard data foundation - an append-only
# audit trail of Package#status changes (Package.status itself stays the
# single current-state source of truth). Populated by a narrow, isolated
# model callback on Package (see PackageStatusTransition/Package) that
# fires only when status actually changes - never for unrelated field
# updates, and never touching Alertable's own after_commit hook.
class CreatePackageStatusTransitions < ActiveRecord::Migration[8.1]
  def change
    create_table :package_status_transitions do |t|
      t.references :package, null: false, foreign_key: true
      t.string :from_status
      t.string :to_status, null: false
      t.datetime :occurred_at, null: false
      t.references :location, polymorphic: true, null: true

      t.datetime :created_at, null: false
    end

    add_index :package_status_transitions, [ :package_id, :occurred_at ]
    add_index :package_status_transitions, :to_status
  end
end
