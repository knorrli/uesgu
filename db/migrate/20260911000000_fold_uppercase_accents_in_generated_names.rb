class FoldUppercaseAccentsInGeneratedNames < ActiveRecord::Migration[8.1]
  ACCENTS_FROM = "äöüàâéèêëïîôûçÄÖÜÀÂÉÈÊËÏÎÔÛÇ".freeze
  ACCENTS_TO   = "aouaaeeeeiioucaouaaeeeeiiouc".freeze
  LEGACY_FROM  = "äöüàâéèêëïîôûç".freeze
  LEGACY_TO    = "aouaaeeeeiiouc".freeze

  FINGERPRINTED = { genres: :name, localities: :name, places: :name }.freeze

  def up
    FINGERPRINTED.each { |table, column| regenerate(table, :fingerprint, fingerprint_sql(column, ACCENTS_FROM, ACCENTS_TO)) }
    regenerate(:places, :name_folded, folded_sql(:name, ACCENTS_FROM, ACCENTS_TO))
  end

  def down
    FINGERPRINTED.each { |table, column| regenerate(table, :fingerprint, fingerprint_sql(column, LEGACY_FROM, LEGACY_TO)) }
    regenerate(:places, :name_folded, folded_sql(:name, LEGACY_FROM, LEGACY_TO))
  end

  private

  def regenerate(table, column, expression)
    index = connection.indexes(table).find { |i| i.columns == [column.to_s] }
    refuse_collisions(table, expression) if index&.unique
    remove_column table, column
    add_column table, column, :virtual, type: :string, as: expression, stored: true
    add_index table, column, unique: index.unique, name: index.name if index
  end

  def refuse_collisions(table, expression)
    clashes = connection.select_rows(<<~SQL.squish)
      SELECT #{expression} AS key, string_agg(name, ', ' ORDER BY name)
      FROM #{table} GROUP BY 1 HAVING count(*) > 1
    SQL
    return if clashes.empty?

    raise "#{table} rows would share a fingerprint once uppercase accents fold: " \
          "#{clashes.map { |key, names| "#{key} (#{names})" }.join('; ')}. " \
          "Merge them by hand first."
  end

  def fingerprint_sql(column, from, to)
    <<~SQL.squish
      regexp_replace(#{translated(column, from, to)}, '[^a-z0-9]', '', 'g')
    SQL
  end

  def folded_sql(column, from, to)
    <<~SQL.squish
      btrim(regexp_replace(#{translated(column, from, to)}, '[^a-z0-9]+', ' ', 'g'))
    SQL
  end

  def translated(column, from, to)
    "translate(replace(replace(lower(#{column}), '&', 'and'), '''n''', 'and'), '#{from}', '#{to}')"
  end
end
