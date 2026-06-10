require 'db_test_helper'

# Locks ApplicationController's locale precedence: a logged-in user's saved
# preference wins, else the first available browser Accept-Language, else the
# default. Tested directly on a controller instance so it stays independent of
# any translated page content.
class SetLocaleTest < ActiveSupport::TestCase
  def build_controller(accept_language: nil)
    env = {}
    env['HTTP_ACCEPT_LANGUAGE'] = accept_language if accept_language
    ApplicationController.new.tap do |c|
      c.set_request!(ActionDispatch::TestRequest.create(env))
      c.set_response!(ActionDispatch::TestResponse.create)
    end
  end

  # set_locale mutates the thread-global I18n.locale; restore it afterwards.
  def with_locale_reset
    original = I18n.locale
    yield
  ensure
    I18n.locale = original
    Current.reset
  end

  test 'browser_locale picks the first available language' do
    c = build_controller(accept_language: 'fr-CH,fr;q=0.9,en;q=0.8')
    assert_equal 'fr', c.send(:browser_locale)
  end

  test 'browser_locale skips unavailable languages' do
    c = build_controller(accept_language: 'es-ES,es;q=0.9,en;q=0.8')
    assert_equal 'en', c.send(:browser_locale)
  end

  test 'browser_locale is nil with no Accept-Language header' do
    assert_nil build_controller.send(:browser_locale)
  end

  test 'set_locale prefers an authenticated users saved locale' do
    with_locale_reset do
      u = user(locale: 'en')
      Current.session = u.sessions.create!
      c = build_controller(accept_language: 'fr') # would otherwise win
      c.define_singleton_method(:authenticated?) { true }

      c.send(:set_locale)

      assert_equal :en, I18n.locale
    end
  end

  test 'set_locale falls back to the browser locale without a preference' do
    with_locale_reset do
      c = build_controller(accept_language: 'fr-CH,fr;q=0.9')
      c.define_singleton_method(:authenticated?) { false }

      c.send(:set_locale)

      assert_equal :fr, I18n.locale
    end
  end

  test 'set_locale falls back to the default locale' do
    with_locale_reset do
      c = build_controller # no header
      c.define_singleton_method(:authenticated?) { false }

      c.send(:set_locale)

      assert_equal I18n.default_locale, I18n.locale
    end
  end
end
