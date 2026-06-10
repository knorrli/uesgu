module Admin
  # Shared gate for the namespaced admin area (accounts + invitations).
  # require_authentication runs first (from the Authentication concern), so
  # guests are sent to login and authenticated non-admins get 403.
  class BaseController < ApplicationController
    before_action :require_admin
  end
end
