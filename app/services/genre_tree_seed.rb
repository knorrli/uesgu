class GenreTreeSeed
  Result = Struct.new(:placed, :tree_entries, :hidden, :blocked, :ignored, :alias_groups, :multi_home, keyword_init: true)

  def self.import(data)
    new(data).import
  end

  def initialize(data)
    @data    = data || {}
    @hidden  = Array(@data["hidden"])
    @blocked = Array(@data["blocked"])
    @ignored = Array(@data["ignored"])
    @aliases = @data["aliases"] || {}
  end

  def import
    @parent_of = flatten_tree(@data["genres"])

    Genre.ensure!(@parent_of.keys + @hidden + @blocked + @ignored + @aliases.keys + @aliases.values.flatten)
    @lookup = Genre.all.index_by(&:fingerprint)

    multi_home = place_tree
    apply_dispositions
    apply_aliases
    Genre.reconcile!

    Result.new(
      placed: Genre.placed.count, tree_entries: @parent_of.size,
      hidden: @hidden.size, blocked: @blocked.size, ignored: @ignored.size,
      alias_groups: @aliases.size, multi_home: multi_home
    )
  end

  private

  def flatten_tree(nodes, parent_name = nil, acc = {})
    Array(nodes).each do |node|
      name, children = node.is_a?(Hash) ? [node["name"], node["children"]] : [node, nil]
      next if name.to_s.strip.empty?

      acc[name] = parent_name
      flatten_tree(children, name, acc)
    end
    acc
  end

  def find(name)
    @lookup[Genre.fingerprint_for(name)]
  end

  def place_tree
    seen = Hash.new { |h, k| h[k] = [] }
    @parent_of.each do |child_name, parent_name|
      child = find(child_name)
      next unless child

      parent = parent_name && find(parent_name)
      next if parent && parent.id == child.id

      seen[child.id] << (parent_name || "(root)")
      child.update_columns(parent_id: parent&.id, ignored_at: nil, hidden_at: nil,
                           blocked_at: nil, canonical_id: nil)
    end
    seen.select { |_id, parents| parents.uniq.size > 1 }.keys
  end

  def apply_dispositions
    @hidden.each  { |name| find(name)&.hide! }
    @blocked.each { |name| find(name)&.block! }
    @ignored.each { |name| find(name)&.ignore! }
  end

  def apply_aliases
    @aliases.each do |canonical_name, alias_names|
      canonical = find(canonical_name)
      Array(alias_names).each do |alias_name|
        genre = find(alias_name)
        genre.merge_into!(canonical) if genre && canonical && genre.id != canonical.id
      end
    end
  end
end
