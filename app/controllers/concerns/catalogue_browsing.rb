module CatalogueBrowsing
  extend ActiveSupport::Concern

  PAGE_SIZE = 50

  private
    def catalogue_param(name, allowed, default:)
      value = params[name].to_s
      allowed.include?(value) ? value : default
    end
end
