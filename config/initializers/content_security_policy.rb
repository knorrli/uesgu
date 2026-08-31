Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.font_src        :self
    policy.img_src         :self, :data, :blob, :https
    policy.object_src      :none
    policy.script_src      :self
    policy.style_src       :self
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :self
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
