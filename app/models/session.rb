class Session < ApplicationRecord
  belongs_to :user
  belongs_to :applied_saved_filter, class_name: "SavedFilter", optional: true
end
