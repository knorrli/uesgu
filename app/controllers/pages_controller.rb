class PagesController < ApplicationController
  # The footer's static pages — what üsgu is and how it handles data. Both are
  # public: someone deciding whether to sign up should be able to read the
  # privacy stance first, without an account.
  allow_unauthenticated_access only: %i[ about privacy ]

  # GET /about
  def about
  end

  # GET /privacy
  def privacy
  end
end
