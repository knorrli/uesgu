class StyleguideController < ApplicationController
  MEDIA_SAMPLES = [
    %w[youtube 3ij9iQ-EKV8],
    %w[vimeo 22439234],
    %w[bandcamp album=1311644285],
    %w[bandcamp track=3204573407],
    %w[soundcloud forss/flickermood],
    %w[soundcloud forss/sets/soulhack],
    %w[soundcloud tracks/2194801731],
    %w[soundcloud playlists/18],
    %w[mixcloud Kartonauten/deeptechtwo-mix],
    %w[spotify artist/0GOXPHVQjnuiU3652BRfMD],
    %w[spotify album/4aawyAB9vmqN3uQ7FjRGTy],
    %w[spotify track/4cOdK2wGLETKBW3PvgPWqT],
    %w[spotify playlist/37i9dQZF1DXcBWIGoYBM5M]
  ].freeze

  before_action :require_admin

  def index; end

  def media
    @events = MEDIA_SAMPLES.each_with_index.map { |(provider, id), i| media_sample(provider, id, position: i) }
  end

  private

  def media_sample(provider, id, position:)
    Event.instantiate(Event.column_defaults.merge(
      "id" => -(position + 1),
      "title" => "#{MediaHelper::MEDIA_PROVIDER_NAMES[provider]} #{id}",
      "start_date" => Date.current.iso8601,
      "start_time" => "#{Date.current.iso8601} 20:#{format('%02d', position)}:00",
      "media" => [{ provider: provider, id: id }].to_json
    ))
  end
end
