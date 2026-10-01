# Waybill search (map autocomplete) matches the typed text against the
# waybill number ignoring case and hyphens ("wb0623" finds WB-062320).
# text_pattern_ops lets that normalized prefix LIKE use the index.
class AddSearchIndexToWaybills < ActiveRecord::Migration[8.1]
  def change
    add_index :waybills, "upper(replace(waybill_number, '-', '')) text_pattern_ops", name: "index_waybills_on_normalized_number"
  end
end
