require "application_system_test_case"
require_relative "../support/canned_extraction_client"

# The capture screen in a real browser. Everything between picking a file and a row
# appearing lives in app/javascript/controllers/capture_controller.js — the canvas
# downscale, one extraction request per input, and every error path — and no other
# suite can reach it: test/integration/capture_test.rb starts at the request the
# client fires.
#
# The provider is canned; the extraction behind it is real (see
# CannedExtractionClient). Copy assertions pin the user's locale because headless
# Chrome asks for English and missing keys fall back to German.
class CaptureScreenTest < ApplicationSystemTestCase
  REQUIRED_LOCALITY = ".capture-candidate input[name$='[locality]']".freeze

  def setup
    @user = user(contributor: true, locale: "de")
    sign_in_as @user
  end

  def teardown
    CannedExtractionClient.uninstall
  end

  test "a picked poster becomes an editable candidate and publishes as an event" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-row", text: "poster.png"
    assert_equal "Zorpcore Nacht", field_value("title")
    assert_equal show_date.to_s, field_value("date")
    # Normalised by EventCapture::Clock on the way here, not by the model, which
    # said "20 Uhr" — proof the row went through the real extraction path.
    assert_equal "20:00", field_value("time")

    assert_difference -> { Event.count } => 1, -> { Place.count } => 1 do
      find(".form-actions input[type=submit]").click
      assert_current_path root_path
    end
    assert_equal "Zorpwil", Place.last.locality
  end

  test "an unreadable file fails its own row while the rest of the batch lands" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "broken.png", "poster.png"

    assert_selector ".capture-row", text: "broken.png"
    assert_selector ".capture-row", text: copy("failures.image_unsupported")
    assert_selector ".capture-candidate", count: 1
    assert_selector ".form-actions input[type=submit]"
  end

  test "a refused request fails the row rather than leaving it pending forever" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    @user.update!(contributor: false)
    pick "poster.png"

    assert_selector ".capture-row", text: copy("failures.unreachable")
    assert_no_selector ".capture-candidate"
    assert_no_selector ".capture-row", text: copy("row.pending")
  end

  test "a provider failure fails the row and leaves the pasted text where it was" do
    CannedExtractionClient.install(raises: "HTTP 503: upstream busy")
    visit capture_path
    paste "Zorpcore Nacht, Zorpsaal, 20 Uhr"

    assert_selector ".capture-row", text: copy("failures.provider_error")
    # The paste is the one input that cannot be picked again from disk.
    assert_equal "Zorpcore Nacht, Zorpsaal, 20 Uhr", find(".capture-picker textarea").value
    assert_no_selector ".form-actions input[type=submit]"
  end

  test "unchecking keep lifts required so a dropped row cannot block the batch" do
    CannedExtractionClient.install(events: [poster_event(locality: nil, canton: nil)])
    visit capture_path
    pick "poster.png"

    assert_selector "#{REQUIRED_LOCALITY}[required]"
    accept_checkbox.click
    assert_no_selector "#{REQUIRED_LOCALITY}[required]"
    accept_checkbox.click
    assert_selector "#{REQUIRED_LOCALITY}[required]"
  end

  private

  # Far enough out that the candidate is never past, which is what decides whether
  # the row arrives kept or dropped.
  def show_date = Date.current + 30

  # The shape EventCapture::Prompt::SCHEMA asks the model for. `date_evidence` cites
  # no date on purpose: YearResolver would otherwise recompute the year from it and
  # move the date this test asserts on.
  def poster_event(**overrides)
    { title: "Zorpcore Nacht", date: show_date.to_s, date_evidence: "steht auf dem Plakat",
      time: "20 Uhr", place: "Zorpsaal", place_evidence: "Zorpsaal", locality: "Zorpwil",
      canton: "BE", genres: ["zorpcore"], source_url: nil }.merge(overrides)
  end

  def pick(*names)
    find("input[type=file]").set(names.map { |name| file_fixture(name) })
  end

  def paste(text)
    find(".capture-picker textarea").set(text)
    find("button[data-action='capture#pickText']").click
  end

  def field_value(field) = find(".capture-candidate input[name$='[#{field}]']").value

  def accept_checkbox = find(".capture-candidate input[name$='[accept]']")

  def copy(key) = I18n.t("capture.#{key}", locale: :de)
end
