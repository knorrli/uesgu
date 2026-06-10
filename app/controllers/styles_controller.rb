class StylesController < ApplicationController
  # Powers the public events filter style combobox.
  allow_unauthenticated_access only: %i[ chips ]

  def chips
    @styles = Style
      .where(id: params[:combobox_values].to_s.split(','))
      .distinct
      .order(name: :asc)

    render turbo_stream: helpers.combobox_selection_chips_for(@styles)
  end
end
