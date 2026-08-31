module Admin
  class DiscardRulesController < BaseController
    def index
      @rules = DiscardRule.by_recency
    end

    def new
      @rule = DiscardRule.new
    end

    def edit
      @rule = DiscardRule.find(params.expect(:id))
    end

    def create
      @rule = DiscardRule.new(rule_params)
      if @rule.save
        DiscardRule.reapply_all!
        redirect_to admin_discard_rules_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @rule = DiscardRule.find(params.expect(:id))
      if @rule.update(rule_params)
        DiscardRule.reapply_all!
        redirect_to admin_discard_rules_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      DiscardRule.find(params.expect(:id)).destroy
      DiscardRule.reapply_all!
      redirect_to admin_discard_rules_path, notice: t(".deleted"), status: :see_other
    end

    def preview
      @rule = DiscardRule.new(pattern: params[:pattern], scraper: params[:scraper].presence)
      if @rule.valid?
        scope = @rule.matching_events
        @total = scope.count
        @events = scope.includes(:locations, :event_saves).order(start_date: :asc).limit(50)
      else
        @total = 0
        @events = Event.none
      end
      render partial: "admin/discard_rules/preview", locals: { events: @events, total: @total }
    end

    private

    def rule_params
      params.expect(discard_rule: %i[pattern scraper active note])
    end
  end
end
