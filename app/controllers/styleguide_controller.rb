# Living styleguide. Admin-only: an internal reference, not a public page. The
# view hand-writes representative markup using the real shared classes, and the
# page pulls in the same `:app` CSS bundle as everything else — so it reflects
# the current styles automatically.
class StyleguideController < ApplicationController
  before_action :require_admin

  def index; end
end
