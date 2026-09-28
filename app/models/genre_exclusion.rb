class GenreExclusion < ApplicationRecord
  belongs_to :user
  belongs_to :genre
end
