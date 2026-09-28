class GenreExclusionsController < ApplicationController
  def create
    current_user.genre_exclusions.create_or_find_by!(genre: excluded_genre)
    redirect_to url_from(params[:return_to]) || root_path, status: :see_other
  end

  def destroy
    genre_id = params.expect(:id)
    current_user.genre_exclusions.where(genre: Genre.where(id: genre_id).or(Genre.where(canonical_id: genre_id))).delete_all
    redirect_to settings_path(anchor: "excluded-genres"), status: :see_other
  end

  private

  def excluded_genre
    genre = Genre.find_by!(fingerprint: Genre.fingerprint_for(params.expect(:name)))
    genre.canonical || genre
  end
end
