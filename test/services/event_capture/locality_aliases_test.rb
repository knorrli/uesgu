require "test_helper"

# The curated list is data, so what is testable about it is its shape: every row has
# to do something, and no row may contradict another.
class EventCapture::LocalityAliasesTest < ActiveSupport::TestCase
  def curated = EventCapture::LocalityAliases.curated

  def variants = curated.canonicals.flat_map { |canonical, names| names.map { |name| [name, canonical] } }

  test "every curated variant resolves to the spelling it is filed under" do
    variants.each { |name, canonical| assert_equal canonical, curated.canonical_for(name) }
  end

  # EventCapture::Localities already folds case, accents and punctuation, so a row
  # whose variant fingerprints to its own canonical changes nothing and reads as if it
  # did.
  test "no curated variant is one the fingerprint already reaches" do
    variants.each do |name, canonical|
      refute_equal Fingerprint.for(canonical), Fingerprint.for(name),
                   "#{name} already folds onto #{canonical}"
    end
  end

  # Two towns claiming one variant is silent — the later row wins and the earlier one
  # simply stops working.
  test "no curated variant is claimed by two localities" do
    keys = variants.map { |name, _| Fingerprint.for(name) }

    assert_equal keys.uniq, keys
  end

  # Aliases do not chain, so a canonical listed as somebody else's variant resolves
  # one way through its own row and another way through theirs.
  test "no curated locality is also somebody's variant" do
    canonicals = curated.canonicals.keys.map { |name| Fingerprint.for(name) }

    variants.each { |name, _| refute_includes canonicals, Fingerprint.for(name) }
  end

  test "a locality with no curated variant resolves to nothing" do
    assert_nil curated.canonical_for("Zorpwil")
    assert_nil curated.canonical_for("")
    assert_nil curated.canonical_for(nil)
  end
end
