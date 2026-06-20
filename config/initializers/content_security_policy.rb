# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.font_src        :self                 # Phosphor.woff2 etc. are local
    policy.img_src         :self, :data, :https
    policy.object_src      :none
    policy.script_src      :self                 # all JS is vendored via importmap
    policy.style_src       :self, :unsafe_inline # some views use inline style= attrs
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :self                 # clickjacking guard
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Per-request nonce for the inline theme script and importmap's inline JSON.
  # Only script-src is nonce-gated (style-src stays unsafe_inline). Random rather
  # than session-based so a nonce is present for signed-out visitors too.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Flip to true to observe violations in the browser console without blocking,
  # then back to enforcing once the report is clean.
  # config.content_security_policy_report_only = true
end
