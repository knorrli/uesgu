# Solid Queue has been removed — scheduled work now runs as Render cron jobs
# (see render.yaml) and nothing enqueues Active Job. Drop its tables. Child
# execution tables are listed before solid_queue_jobs (which they reference);
# force: :cascade also clears any remaining FKs.
class DropSolidQueueTables < ActiveRecord::Migration[8.0]
  TABLES = %w[
    solid_queue_recurring_executions
    solid_queue_blocked_executions
    solid_queue_claimed_executions
    solid_queue_failed_executions
    solid_queue_ready_executions
    solid_queue_scheduled_executions
    solid_queue_semaphores
    solid_queue_pauses
    solid_queue_processes
    solid_queue_recurring_tasks
    solid_queue_jobs
  ].freeze

  def up
    TABLES.each { |table| drop_table(table, if_exists: true, force: :cascade) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
