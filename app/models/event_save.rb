# A user bookmarking a single event ("save this show") — distinct from following
# a location or style.
class EventSave < ApplicationRecord
  belongs_to :user
  belongs_to :event

  validates :event_id, uniqueness: { scope: :user_id }
end
