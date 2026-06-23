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
    policy.style_src       :self                 # CSS is external; sole inline <style> (Turbo's progress bar) is nonced below
    policy.base_uri        :self
    policy.form_action     :self
    policy.frame_ancestors :self                 # clickjacking guard
    # policy.report_uri "/csp-violation-report-endpoint"
  end

  # Per-request nonce, random rather than session-based so a nonce is present
  # for signed-out visitors too. It covers:
  #   - script-src: the inline theme script and importmap's inline JSON.
  #   - style-src:  Turbo's navigation progress bar injects one inline <style>
  #     (.turbo-progress-bar) into <head> and stamps this nonce onto it. Without
  #     style-src in the nonce directives the browser has no nonce to match and
  #     blocks it — a recurring (cosmetic) CSP console violation. Noncing the
  #     directive keeps style-src at 'self' + 'nonce-…' (no 'unsafe-inline').
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # Flip to true to observe violations in the browser console without blocking,
  # then back to enforcing once the report is clean.
  # config.content_security_policy_report_only = true
end
