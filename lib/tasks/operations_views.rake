# Applies the read-only SQL views under db/operations_views/ to the
# operations database. Deliberately NOT an ActiveRecord::Migration - these
# are Command Centre reporting views (Phase 2, SQL-views-only), not schema
# changes, and must never touch db/operations_schema.rb or bump its
# version. Every statement is `CREATE OR REPLACE VIEW`, so re-running this
# task is always safe. Files are applied in filename order, which is also
# their dependency order (e.g. 02_vw_hub_dashboard_overview.sql selects
# from the view created by 01_vw_hub_dashboard_summary.sql).
namespace :db do
  namespace :operations_views do
    desc "Create/replace the Command Centre reporting views in the operations database"
    task apply: :environment do
      views_dir = Rails.root.join("db", "operations_views")
      sql_files = Dir.glob(views_dir.join("*.sql")).sort

      abort "No SQL view files found in #{views_dir}" if sql_files.empty?

      OperationsRecord.connection.transaction do
        sql_files.each do |file|
          puts "Applying #{File.basename(file)}"
          OperationsRecord.connection.execute(File.read(file))
        end
      end

      puts "Applied #{sql_files.size} view definition(s) to the operations database."
    end
  end
end
