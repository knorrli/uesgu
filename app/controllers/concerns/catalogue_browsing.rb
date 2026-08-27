# The param half of a catalogue browser — admin events / localities / locations /
# places and the genre index, the five pages built on shared/_catalogue_controls.
# Each reads a filter param, a sort param and a page, all of which arrive from the
# open web and so have to be whitelisted before they reach a scope.
#
# Only the params are shared. Two of the five cannot be queried in SQL at all
# (locations have no table of their own; places sort by a tagging count that is not
# on the record), so scope building stays with each controller.
module CatalogueBrowsing
  extend ActiveSupport::Concern

  PAGE_SIZE = 50

  private
    # `allowed` is whatever the controller already keeps: a Hash mapping each value
    # to the scope it dispatches to, or a bare Array where there is nothing to map.
    # Hash#include? tests keys, so both answer the same question here.
    def catalogue_param(name, allowed, default:)
      value = params[name].to_s
      allowed.include?(value) ? value : default
    end
end
