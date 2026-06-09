class FavoritesController < ApplicationController
  before_action :set_user

  # Maps the inline toggle's `type` to the user's tag list. Locations and styles
  # are the only things a user can follow (genres stay internal).
  TOGGLE_LISTS = { 'location' => :location_list, 'style' => :style_list }.freeze

  def show
  end

  def update
    if @user.update(favorites_params)
      redirect_to favorites_path, notice: t('favorites.saved')
    else
      render :show, status: :unprocessable_entity
    end
  end

  # Follow/unfollow a single location or style from the events list. Optimistic:
  # the favorite Stimulus controller has already flipped the heart, so we just
  # persist and answer with no body.
  def toggle
    list_name = TOGGLE_LISTS[params[:type]]
    value = params[:value].to_s.strip
    return head :unprocessable_entity if list_name.nil? || value.blank?

    list = @user.public_send(list_name)
    list.include?(value) ? list.remove(value) : list.add(value)
    @user.save!
    head :no_content
  end

  private

  def set_user
    @user = Current.user
  end

  def favorites_params
    params.expect(user: [{ location_list: [], style_list: [] }])
  end
end
