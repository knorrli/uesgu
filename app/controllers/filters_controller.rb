class FiltersController < ApplicationController
  allow_unauthenticated_access

  def index
    @filters = Filter.ransack(name_cont: params[:q]).result.order(name: :asc)
  end

  def show
    @filter = Filter.find(params[:id])

    respond_to do |format|
      format.html do
        redirect_to events_path(f: @filter.id)
      end

      format.ics do
        cal = Icalendar::Calendar.new
        cal.x_wr_calname = "üsgu - #{@filter.name}"
        @filter.events.group_by(&:start_date).each do |date, events|
          sorted_events = events.sort_by { |e| e.locations.sort }
          cal.event do |e|
            e.dtstart = Icalendar::Values::Date.new(date.strftime('%Y%m%d'))
            e.uid = "uesgu.ch@#{@filter.id}-#{date.strftime('%Y%m%d')}"
            e.summary = "#{events.count} #{Event.model_name.human(count: events.count)}"
            e.description = sorted_events.map do |event|
              locations = event.locations.join(', ')
              title = event.title
              tags = (event.styles + event.genres).uniq.sort.join(', ')

              buffer = StringIO.new
              buffer << "#{locations}: #{title}"
              if tags.present?
                buffer << " [#{tags}]"
              end
              buffer.string
            end.join("\n------------\n")
          end
        end
        cal.publish
        render plain: cal.to_ical
      end
    end
  end

  def new
    @filter = Filter.new
  end

  def create
    @filter = Filter.new(filter_params)
    if @filter.save
      redirect_to events_path(f: @filter.id)
    else
      redirect_to events_path(@filter.to_params)
    end
  end

  def update
    @filter = Filter.find(params[:id])

    if @filter.update(filter_params)
      redirect_to events_path(f: @filter.id)
    else
      redirect_to events_path(@filter.to_params.except(:f))
    end
  end

  def destroy
    @filter = Filter.find(params[:id])
    @filter.destroy
    redirect_to events_path
  end

  def filter_params
    joined_params = params.expect(
      filter: [
        :name,
        :queries,
        :location_list,
        :style_list,
        :genre_list,
        :date_ranges
      ]
    )

    { **joined_params, date_ranges: joined_params[:date_ranges]&.split(',') }.with_indifferent_access
  end
end
