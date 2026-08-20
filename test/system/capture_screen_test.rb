require "application_system_test_case"
require_relative "../support/canned_extraction_client"

# The capture screen in a real browser. Everything between picking a file and a
# decision lives in app/javascript/controllers/capture_controller.js, and no other
# suite reaches it: test/integration/capture_test.rb starts at the request the client
# fires.
#
# Capybara ignores hidden elements, so a bare `.capture-card` selector is the card on
# screen; `visible: :all` is how the queue behind it is counted. Copy assertions pin
# the locale because headless Chrome asks for English and missing keys fall back to
# German.
class CaptureScreenTest < ApplicationSystemTestCase
  def setup
    @user = user(contributor: true, locale: "de")
    sign_in_as @user
  end

  def teardown
    CannedExtractionClient.uninstall
  end

  test "a picked poster becomes an editable card and publishes the moment it is accepted" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_equal "Zorpcore Nacht", field_value("title")
    assert_equal show_date.to_s, field_value("date")
    # Normalised by EventCapture::Clock on the way here, not by the model, which
    # said "20 Uhr" — proof the card went through the real extraction path.
    assert_equal "20:00", field_value("time")

    assert_difference -> { Event.count } => 1, -> { Place.count } => 1 do
      accept
      assert_selector ".capture-queue__tile[data-state=published]"
    end
    assert_equal "Zorpwil", Place.last.locality
    assert_selector "[data-capture-target=done]"
  end

  test "a rejected card publishes nothing and hands over to the next one" do
    CannedExtractionClient.install(events: [poster_event, poster_event(title: "Zorpcore Matinee")])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-card", count: 1, visible: true
    assert_selector ".capture-card", count: 2, visible: :all

    assert_no_difference -> { Event.count } do
      reject
      assert_selector ".capture-queue__tile[data-state=dropped]"
    end
    assert_equal "Zorpcore Matinee", field_value("title")
  end

  test "a refusal stays on its own card instead of taking the queue with it" do
    CannedExtractionClient.install(events: [poster_event(canton: nil)])
    visit capture_path
    pick "poster.png"

    # `required` would stop the submit before the server ever saw it, so it is
    # dropped through the DOM: the point is that the card survives a server refusal.
    assert_selector ".capture-card select[name=canton]"
    execute_script("document.querySelector('.capture-card [name=canton]').removeAttribute('required')")
    accept

    assert_selector ".capture-card__status--refused", text: copy("errors.incomplete")
    assert_empty Event.all
    assert_no_selector "[data-capture-target=done]"
  end

  test "a decided card is still reachable from its tile" do
    CannedExtractionClient.install(events: [poster_event, poster_event(title: "Zorpcore Matinee")])
    visit capture_path
    pick "poster.png"

    reject
    assert_equal "Zorpcore Matinee", field_value("title")

    first(".capture-queue__tile").click
    assert_equal "Zorpcore Nacht", field_value("title")
  end

  test "the venue read off one act on a poster fills in the acts that did not print it" do
    CannedExtractionClient.install(events: [poster_event, matinee(place: nil, place_evidence: nil,
                                                                 locality: nil, canton: nil)])
    visit capture_path
    pick "poster.png"

    reject
    assert_equal "Zorpcore Matinee", field_value("title")
    assert_equal "Zorpsaal", field_value("place")
    assert_equal "Zorpwil", field_value("locality")
    assert_equal "BE", field_value("canton")
  end

  test "a typed locality reaches the sibling cards without overwriting a venue of their own" do
    CannedExtractionClient.install(events: [poster_event(locality: nil, canton: nil),
                                            matinee(place: "Zorpwiler Rathaus", place_evidence: "Rathaus",
                                                    locality: nil, canton: nil)])
    visit capture_path
    pick "poster.png"

    type "locality", "Zorpwil"
    reject
    assert_equal "Zorpcore Matinee", field_value("title")
    assert_equal "Zorpwil", field_value("locality")
    assert_equal "Zorpwiler Rathaus", field_value("place")
  end

  test "a place typed on one input stays on it rather than reaching the next input's cards" do
    CannedExtractionClient.install(events: [poster_event(locality: nil, canton: nil)])
    visit capture_path
    pick "poster.png"
    assert_selector ".capture-card", count: 1, visible: :all
    paste "Zorpcore Nacht, Zorpsaal"
    assert_selector ".capture-card", count: 2, visible: :all

    type "locality", "Zorpwil"
    reject
    assert_equal "", field_value("locality")
  end

  test "a picked poster is rendered beside the fields it produced" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_match(/\Ablob:/, find(".capture-card .review-card__source img")[:src])
    assert_decoded ".capture-card:not([hidden]) .review-card__source img"
  end

  test "a pasted text keeps its excerpt beside the card" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    paste "Zorpcore Nacht, Zorpsaal, 20 Uhr"

    assert_selector ".capture-row__excerpt", text: "Zorpcore Nacht, Zorpsaal, 20 Uhr"
  end

  test "an unreadable file fails its own row while the rest of the batch lands" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "broken.png", "poster.png"

    assert_selector ".capture-row", text: copy("failures.image_unsupported")
    assert_selector ".capture-card", count: 1, visible: :all
  end

  test "a refused request fails the row rather than leaving it pending forever" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    @user.update!(contributor: false)
    pick "poster.png"

    assert_selector ".capture-row", text: copy("failures.unreachable")
    assert_no_selector ".capture-card", visible: :all
    assert_no_selector ".capture-row", text: copy("row.pending")
  end

  test "a provider failure fails the row and leaves the pasted text where it was" do
    CannedExtractionClient.install(raises: "HTTP 503: upstream busy")
    visit capture_path
    paste "Zorpcore Nacht, Zorpsaal, 20 Uhr"

    assert_selector ".capture-row", text: copy("failures.provider_error")
    # The paste is the one input that cannot be picked again from disk.
    assert_equal "Zorpcore Nacht, Zorpsaal, 20 Uhr", find(".capture-picker textarea").value
    assert_no_selector ".capture-card", visible: :all
  end

  private

  # Far enough out that the candidate is never past.
  def show_date = Date.current + 30

  # The shape EventCapture::Prompt::SCHEMA asks the model for. `date_evidence` cites
  # no date on purpose: YearResolver would otherwise recompute the year from it and
  # move the date this test asserts on.
  def poster_event(**overrides)
    { title: "Zorpcore Nacht", date: show_date.to_s, date_evidence: "steht auf dem Plakat",
      time: "20 Uhr", place: "Zorpsaal", place_evidence: "Zorpsaal", locality: "Zorpwil",
      canton: "BE", genres: ["zorpcore"], source_url: nil }.merge(overrides)
  end

  def matinee(**overrides) = poster_event(title: "Zorpcore Matinee", **overrides)

  # Blurred on purpose: the carry hangs off `change`, which a text field fires when it
  # is left, not on every keystroke.
  def type(field, value)
    find(".capture-card [name='#{field}']").set(value)
    find(".capture-card [name=title]").click
  end

  def pick(*names)
    find("input[type=file]").set(names.map { |name| file_fixture(name) })
  end

  def paste(text)
    find(".capture-picker textarea").set(text)
    find("button[data-action='capture#pickText']").click
  end

  def accept = find(".capture-card .action-bar input[type=submit]").click

  def reject = find(".capture-card .action-bar button").click

  def field_value(field) = find(".capture-card [name='#{field}']").value

  def copy(key, **args) = I18n.t("capture.#{key}", locale: :de, **args)

  # A src attribute only proves the slot was filled. naturalWidth is the one signal
  # Chrome gives that the blob: URL was actually allowed to load — a CSP without
  # blob: in img-src leaves the element in place and the image at zero.
  def assert_decoded(selector)
    find(selector)
    page.document.synchronize(errors: [Minitest::Assertion]) do
      assert_operator evaluate_script("document.querySelector('#{selector}').naturalWidth"), :>, 0
    end
  end
end
