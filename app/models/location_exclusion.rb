class LocationExclusion < ApplicationRecord
  belongs_to :user

  def self.rename_all
    find_each do |exclusion|
      renamed = yield(exclusion.name)
      next if renamed.nil? || renamed == exclusion.name

      if where(user_id: exclusion.user_id, name: renamed).exists?
        exclusion.destroy!
      else
        exclusion.update!(name: renamed)
      end
    end
  end
end
