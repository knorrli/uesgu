class InstallController < ApplicationController
  # Installing the app is the most important first step and shouldn't require an
  # account — anyone can land here and add üsgu to their phone.
  allow_unauthenticated_access only: %i[ show ]

  def show
  end
end
