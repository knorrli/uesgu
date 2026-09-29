class RateLimitsController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  def show
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append_all(".flashes", partial: "rate_limits/flash"),
               status: :too_many_requests
      end
      format.any { render :show, formats: :html, status: :too_many_requests }
    end
  end
end
