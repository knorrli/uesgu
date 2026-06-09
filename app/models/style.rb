class Style < ApplicationRecord
  has_and_belongs_to_many :genres

  def to_s
    name
  end

  def to_combobox_display
    name
  end
end
