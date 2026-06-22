require 'db_test_helper'

# DiscardRule: admin-authored text rules that auto-filter junk scraped events.
# Asserts the match semantics + the single-source-of-truth reapply sweep, using
# invented event text (never real taxonomy).
class DiscardRuleTest < ActiveSupport::TestCase
  test 'pattern must be present and at least 2 chars' do
    assert DiscardRule.new(pattern: 'ab').valid?
    refute DiscardRule.new(pattern: 'a').valid?
    refute DiscardRule.new(pattern: '').valid?
  end

  test 'matches? is a case-insensitive substring of title or description' do
    rule = DiscardRule.new(pattern: 'zorp')
    assert rule.matches?(title: 'A ZORPball night', description: nil, location: 'X')
    assert rule.matches?(title: 'Nothing', description: 'late zorp show', location: 'X')
    refute rule.matches?(title: 'Nothing', description: 'here', location: 'X')
  end

  test 'matches? respects the venue gate' do
    rule = DiscardRule.new(pattern: 'zorp', scraper: 'Venue A')
    assert rule.matches?(title: 'zorp', description: nil, location: 'Venue A')
    refute rule.matches?(title: 'zorp', description: nil, location: 'Venue B')
  end

  test 'matching_events finds kept events by title/description, scoped to the venue' do
    here = event(title: 'zorp fest', location_list: ['Venue A', 'Town', 'XX'])
    elsewhere = event(title: 'zorp fest', location_list: ['Venue B', 'Town', 'XX'])
    event(title: 'real concert', location_list: ['Venue A', 'Town', 'XX'])

    global = DiscardRule.new(pattern: 'zorp')
    assert_equal [here, elsewhere].map(&:id).sort, global.matching_events.pluck(:id).sort

    scoped = DiscardRule.new(pattern: 'zorp', scraper: 'Venue A')
    assert_equal [here.id], scoped.matching_events.pluck(:id)
  end

  test 'matching_events ignores dismissed events' do
    gone = event(title: 'zorp fest')
    gone.dismiss!
    assert_empty DiscardRule.new(pattern: 'zorp').matching_events
  end

  test 'percent and underscore in a pattern are matched literally' do
    matching = event(title: '50% off night')
    event(title: '5012 off night')
    assert_equal [matching.id], DiscardRule.new(pattern: '50%').matching_events.pluck(:id)
  end

  test 'reapply_all! flags matching events, clears the rest, first rule wins' do
    junk = event(title: 'zorp fest')
    keep = event(title: 'real concert')

    rule = DiscardRule.create!(pattern: 'zorp')
    DiscardRule.reapply_all!
    assert_equal rule.id, junk.reload.discarded_by_rule_id
    assert_nil keep.reload.discarded_by_rule_id

    # Deleting the rule (and reapplying) releases the event.
    rule.destroy
    DiscardRule.reapply_all!
    assert_nil junk.reload.discarded_by_rule_id
  end

  test 'an inactive rule discards nothing' do
    junk = event(title: 'zorp fest')
    DiscardRule.create!(pattern: 'zorp', active: false)
    DiscardRule.reapply_all!
    assert_nil junk.reload.discarded_by_rule_id
  end

  test 'discarded events drop out of the visible scope' do
    junk = event(title: 'zorp fest')
    DiscardRule.create!(pattern: 'zorp')
    DiscardRule.reapply_all!
    refute Event.visible.exists?(junk.id)
    assert Event.discarded.exists?(junk.id)
  end
end
