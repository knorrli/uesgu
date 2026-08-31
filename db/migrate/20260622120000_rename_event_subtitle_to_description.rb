class RenameEventSubtitleToDescription < ActiveRecord::Migration[8.0]
  def up
    rename_column :events, :subtitle, :description
    rename_overridden_lock(from: 'subtitle', to: 'description')
  end

  def down
    rename_column :events, :description, :subtitle
    rename_overridden_lock(from: 'description', to: 'subtitle')
  end

  private

  def rename_overridden_lock(from:, to:)
    execute(<<~SQL.squish)
      UPDATE events
      SET overridden_fields = (
        SELECT jsonb_agg(
          CASE WHEN elem = to_jsonb('#{from}'::text) THEN to_jsonb('#{to}'::text) ELSE elem END
        )
        FROM jsonb_array_elements(overridden_fields) elem
      )
      WHERE overridden_fields @> to_jsonb(ARRAY['#{from}']::text[]);
    SQL
  end
end
