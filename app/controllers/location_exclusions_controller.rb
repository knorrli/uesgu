class LocationExclusionsController < ApplicationController
  def create
    current_user.location_exclusions.create_or_find_by!(name: excluded_location.name)
    redirect_to url_from(params[:return_to]) || root_path, status: :see_other
  end

  def destroy
    current_user.location_exclusions.find(params.expect(:id)).destroy!
    redirect_to settings_path(anchor: "excluded-locations"), status: :see_other
  end

  private

  def excluded_location
    ActsAsTaggableOn::Tag.for_context("locations").find_by!(name: params.expect(:name))
  end
end
