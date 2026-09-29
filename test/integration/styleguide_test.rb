require "db_test_helper"

class StyleguideTest < ActionDispatch::IntegrationTest
  test "guests are sent to login" do
    get styleguide_path
    assert_redirected_to new_session_path
  end

  test "authenticated non-admins are forbidden" do
    sign_in_as user(admin: false)
    get styleguide_path
    assert_response :forbidden
  end

  test "admins get the rendered styleguide" do
    sign_in_as user(admin: true)
    get styleguide_path

    assert_response :success
    assert_select "h1", text: /styleguide/i
    assert_select "input[type=submit]"
    assert_select ".button-small.danger"
    assert_select ".icon-button.danger"
    assert_select ".scrape-badge--ok"
    assert_select ".funnel-fill"
    assert_select ".suggestions .chip"
    assert_select ".field-group__attached"
    assert_select ".drop-zone__target"
    assert_select ".text-page .prose h3"
    assert_select ".day-nav .range-cal"
  end

  test "the player bench is admin-only" do
    get styleguide_media_path
    assert_redirected_to new_session_path

    sign_in_as user(admin: false)
    get styleguide_media_path
    assert_response :forbidden
  end

  test "the player bench has a feed row with a play button for every sample reference" do
    sign_in_as user(admin: true)
    get styleguide_media_path

    assert_response :success
    assert_select "#events .event .event-play", count: StyleguideController::MEDIA_SAMPLES.size
    assert_equal StyleguideController::MEDIA_SAMPLES.map(&:first).uniq,
                 css_select(".event-play").map { |button| button["data-media-play-provider-value"] }.uniq
    assert_select "iframe", count: 0
  end
end
