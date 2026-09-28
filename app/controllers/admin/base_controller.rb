module Admin
  class BaseController < ApplicationController
    class_attribute :required_permission, default: nil

    before_action :require_area_access

    def self.requires(permission) = self.required_permission = permission

    private

    def require_area_access
      required_permission ? require_permission(required_permission) : require_admin
    end
  end
end
