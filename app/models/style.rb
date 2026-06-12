class Style < ApplicationRecord
  has_and_belongs_to_many :genres

  # How many events carry each style, keyed by style name. Styles tag events
  # through acts_as_taggable_on (:styles context), where the tag name is the
  # style name — so usage lives in the taggings, not on a column here. One
  # grouped query feeds the admin styles browser.
  def self.event_usage_counts
    ActsAsTaggableOn::Tagging
      .where(context: 'styles', taggable_type: Event.name)
      .joins(:tag)
      .group('tags.name')
      .count
  end

  def to_s
    name
  end

  def to_combobox_display
    name
  end
end
