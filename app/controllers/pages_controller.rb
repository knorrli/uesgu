class PagesController < ApplicationController
  allow_unauthenticated_access only: %i[ about privacy ]

  def about
  end

  def privacy
  end
end
