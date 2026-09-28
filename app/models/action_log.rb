class ActionLog < ApplicationRecord
  AREAS = {
    "event" => "events",
    "genre" => "genres",
    "place" => "places", "locality" => "places",
    "invitation" => "invites",
    "user" => "admin", "scrape" => "admin", "discard_rule" => "admin"
  }.freeze

  UNDOABLE = %w[event.edit event.revert event.dismiss event.restore event.merge event.unmerge].freeze

  UNDO = "undo".freeze

  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :reverts, class_name: "ActionLog", optional: true, inverse_of: :reversal
  has_one :reversal, class_name: "ActionLog", foreign_key: :reverts_id, inverse_of: :reverts,
                     dependent: :restrict_with_exception

  validates :action, :area, presence: true

  scope :newest_first, -> { order(id: :desc) }

  def self.track(action, subject, user: Current.user, reverts: nil, label: nil, **details)
    before = snapshot_of(subject)
    transaction do
      yield
      record!(action, subject, before: before, user: user, reverts: reverts, label: label, **details)
    end
  end

  def self.record!(action, subject, before: nil, user: Current.user, reverts: nil, label: nil, **details)
    after = snapshot_of(subject)
    changed = before.to_h.reject { |key, value| after.to_h[key] == value }
    return if before && changed.empty?

    create!(action: action, area: reverts&.area || AREAS.fetch(action.split(".").first),
            subject: subject, subject_label: label || label_for(subject), before: changed.as_json,
            details: details.as_json, user: user, reverts: reverts)
  end

  def self.snapshot_of(subject) = subject.try(:undo_snapshot)

  def self.label_for(subject) = subject.try(:title) || subject.try(:username) || subject.try(:name) || subject.to_s

  def undo? = action == UNDO

  def undoable_action? = UNDOABLE.include?(action)

  def undoable? = undoable_action? && subject.present? && superseded_by.nil?

  def superseded_by
    return if subject_id.nil?

    @superseded_by ||= ActionLog.where(subject_type: subject_type, subject_id: subject_id)
                                .where("id > ?", id).order(:id).first
  end

  def undo!(user: Current.user)
    raise ArgumentError, "this action can no longer be undone" unless undoable?

    ActionLog.track(UNDO, subject, user: user, reverts: self) { subject.restore_snapshot!(before) }
  end
end
