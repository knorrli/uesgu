class RenameEventSubtitleToDescription < ActiveRecord::Migration[8.0]
  # `subtitle` had drifted into a general "best secondary text we have" field — a
  # short tagline for one venue, a support-act line or lineup for another, the
  # first blurb paragraph for a third (and a useless title-dup for nouveau_monde).
  # Rename it to `description` so the column name matches that general meaning.
  # Deliberately NOT a second column alongside subtitle: one general field beats a
  # subtitle/description pair that rots into "which one wins?". Per-source curation
  # of what fills it is a follow-up.
  def up
    rename_column :events, :subtitle, :description
    rename_overridden_lock(from: 'subtitle', to: 'description')
  end

  def down
    rename_column :events, :description, :subtitle
    rename_overridden_lock(from: 'description', to: 'subtitle')
  end

  private

  # Keep the field-level admin locks (Event#overridden_fields, a jsonb array of
  # field-name strings) consistent with the column name. Expected to touch zero
  # rows — no subtitle has been manually locked — but written so the rename stays
  # correct even if one is locked between now and deploy. Idempotent.
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
