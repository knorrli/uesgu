class FavoritesController < ApplicationController
  before_action :set_user

  def show
  end

  def update
    if @user.update(favorites_params)
      redirect_to favorites_path, notice: t('favorites.saved')
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_user
    @user = Current.user
  end

  def favorites_params
    params.expect(user: [{ location_list: [], style_list: [] }])
  end
end
