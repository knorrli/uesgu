# Loads a curated genre tree (the parsed db/genres.yml hash) into the database:
# upsert a Genre per name (matched/deduped by fingerprint via Genre.ensure!), set
# each genre's parent from the YAML nesting, and apply the hidden/blocked/ignored
# dispositions and aliases. Idempotent — re-running converges. Genres NOT named in
# the seed are left untouched, so new scrapes stay unplaced in the curation queue.
#
# The rake task taxonomy:import_tree is a thin wrapper that reads the YAML and
# hands the hash here; this object holds the logic so it's unit-testable with
# synthetic data. See docs/taxonomy-and-saved-filters-redesign.md.
class GenreTreeSeed
  Result = Struct.new(:placed, :tree_entries, :hidden, :blocked, :ignored, :alias_groups, :multi_home, keyword_init: true)

  def self.import(data)
    new(data).import
  end

  def initialize(data)
    @data    = data || {}
    @hidden  = Array(@data['hidden'])
    @blocked = Array(@data['blocked'])
    @ignored = Array(@data['ignored'])
    @aliases = @data['aliases'] || {}
  end

  def import
    @parent_of = flatten_tree(@data['genres'])

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

  # Flatten the nested tree into { name => parent name } (nil parent = root). A
  # node is either a bare string leaf or a { 'name' =>, 'children' => [...] } hash.
  def flatten_tree(nodes, parent_name = nil, acc = {})
    Array(nodes).each do |node|
      name, children = node.is_a?(Hash) ? [node['name'], node['children']] : [node, nil]
      next if name.to_s.strip.empty?

      acc[name] = parent_name
      flatten_tree(children, name, acc)
    end
    acc
  end

  def find(name)
    @lookup[Genre.fingerprint_for(name)]
  end

  # Tree placement first; dispositions/aliases below clear parent_id and so win if
  # a hand-edited seed lists a genre in both the tree and a disposition list.
  # Returns the names that resolved to a genre listed under more than one parent
  # (the tree is single-parent, so the last write wins — a heads-up, not an error).
  def place_tree
    seen = Hash.new { |h, k| h[k] = [] }
    @parent_of.each do |child_name, parent_name|
      child = find(child_name)
      next unless child

      parent = parent_name && find(parent_name)
      # A child whose fingerprint collapses onto its parent (e.g. "pop" under root
      # "Pop") IS that genre — leave it put rather than tripping the not-self check.
      next if parent && parent.id == child.id

      seen[child.id] << (parent_name || '(root)')
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
