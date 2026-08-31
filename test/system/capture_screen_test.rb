require "application_system_test_case"
require_relative "../support/canned_extraction_client"

class CaptureScreenTest < ApplicationSystemTestCase
  def setup
    @user = user(contributor: true, locale: "de")
    @staged_paths = []
    sign_in_as @user
  end

  def teardown
    CannedExtractionClient.uninstall
    @staged_paths.each { |path| File.delete(path) if File.exist?(path) }
  end

  test "a picked poster becomes an editable card and publishes the moment it is accepted" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_equal "Zorpcore Nacht", field_value("title")
    assert_equal show_date.to_s, field_value("date")
    assert_equal "20:00", field_value("time")

    assert_difference -> { Event.count } => 1, -> { Place.count } => 1 do
      accept
      assert_published
    end
    assert_equal "Zorpwil", Place.last.locality
    assert_selector ".capture-picker"
  end

  test "the date and time on a card are both native pickers" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_equal "date", field_type("date")
    assert_equal "time", field_type("time")
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

  test "each field carries the text the model quoted as its source" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_selector ".review-card__cite", text: cite("3000 Zorpwil")
    assert_selector ".review-card__cite", text: cite("Zorpsaal")
    assert_selector ".review-card__cite", text: cite("steht auf dem Plakat")
  end

  test "a field the model left empty shows no quote" do
    CannedExtractionClient.install(events: [poster_event(place: nil)])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".review-card__cite", text: cite("Zorpsaal")
    assert_selector ".review-card__cite", text: cite("3000 Zorpwil")
  end

  test "an edited field is reported as a correction against what the model proposed" do
    CannedExtractionClient.install(events: [poster_event(locality: "Us", locality_evidence: "Us")])
    visit capture_path
    pick "poster.png"

    type("locality", "Zorpwil")
    accept
    assert_published

    locality = ExtractionFieldOutcome.find_by(field: "locality")
    assert_predicate locality, :corrected?
    assert_equal "Us", locality.proposed
    assert_equal "Zorpwil", locality.accepted
  end

  test "the strip numbers what it found and says the tiles can be tapped" do
    CannedExtractionClient.install(events: [poster_event, matinee])
    visit capture_path
    pick "poster.png"

    assert_equal %w[1 2], all(".capture-queue__tile[data-card]").map { |tile| tile["data-index"] }
    assert_selector ".page-header", text: copy("review.hint")
  end

  test "a queue of one is already open, so it is not told to tap anything" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-queue__tile[data-card]"
    assert_no_selector ".page-header", text: copy("review.hint")
  end

  test "the genres the model read arrive as chips and publish as they are" do
    CannedExtractionClient.install(events: [poster_event(genres: %w[zorpcore flarncore])])
    visit capture_path
    pick "poster.png"

    assert_selector ".hw-combobox__chip", text: "zorpcore"
    assert_selector ".hw-combobox__chip", text: "flarncore"

    accept
    assert_published
    assert_equal %w[Flarncore Zorpcore], Event.sole.genre_list.sort
  end

  test "the genre field opens a list, not a dialog, on a phone" do
    genre(name: "zorpwave", events_count: 3)
    CannedExtractionClient.install(events: [poster_event(genres: [])])
    visit capture_path
    pick "poster.png"
    page.current_window.resize_to(390, 844)

    find(".capture-card [role=combobox]").send_keys("zorpw")

    assert_selector ".capture-card .hw-combobox__listbox [role=option]", text: "zorpwave"
    assert_no_selector ".capture-card dialog.hw-combobox__dialog[open]"
  end

  test "the genre options sit in one card at a time" do
    2.times { |i| genre(name: "zorpwave#{i}", events_count: 3) }
    CannedExtractionClient.install(events: [poster_event(genres: []), matinee(genres: [])])
    visit capture_path
    pick "poster.png"

    assert_equal 2, all(".capture-card [role=option]", visible: :all).size

    jump_to 1
    assert_equal 2, all(".capture-card [role=option]", visible: :all).size

    find(".capture-card [role=combobox]").send_keys("zorpwave0")
    assert_selector ".capture-card .hw-combobox__listbox [role=option]", count: 1
  end

  test "a genre already on the card is not offered again" do
    picked = genre(name: "zorpwave", events_count: 3)
    genre(name: "zorpstep", events_count: 3)
    CannedExtractionClient.install(events: [poster_event(genres: [picked.name])])
    visit capture_path
    pick "poster.png"

    find(".capture-card [role=combobox]").send_keys("zorp")

    assert_selector ".capture-card .hw-combobox__listbox [role=option]", text: "zorpstep"
    assert_no_selector ".capture-card .hw-combobox__listbox [role=option]", text: picked.name
  end

  test "tapping a genre chip's remover on a phone takes the genre off" do
    CannedExtractionClient.install(events: [poster_event(genres: %w[zorpcore flarncore])])
    visit capture_path
    pick "poster.png"
    page.current_window.resize_to(390, 844)

    find(".hw-combobox__chip", text: "zorpcore").find(".hw-combobox__chip__remover").click

    assert_no_selector ".hw-combobox__chip", text: "zorpcore"
    assert_selector ".hw-combobox__chip", text: "flarncore"
  end

  test "a genre row full of chips keeps a typable box beside the handle" do
    CannedExtractionClient.install(events: [poster_event(genres: %w[zorpcore flarncore dubtronica])])
    visit capture_path
    pick "poster.png"
    page.current_window.resize_to(390, 844)

    input = rect(".capture-card .hw-combobox__input")
    chip = all(".capture-card .hw-combobox__chip").first.evaluate_script("this.getBoundingClientRect().toJSON()")
    assert_operator input["top"], :>=, chip["bottom"],
      "the chips do not fill the row, so this is not the wrapped case"
    assert_in_delta input["top"], rect(".capture-card .hw-combobox__handle")["top"], 1
    assert_operator input["width"], :>=, 96
  end

  test "a genre the taxonomy has never seen can still be typed in" do
    genre(name: "zorpwave", events_count: 3)
    CannedExtractionClient.install(events: [poster_event(genres: [])])
    visit capture_path
    pick "poster.png"

    add_genre "dubtronica"

    assert_selector ".hw-combobox__chip", text: "dubtronica"
    accept
    assert_published
    assert_equal %w[Dubtronica], Event.sole.genre_list
  end

  test "a slash run the taxonomy vouches for arrives as one chip per genre" do
    carried = genre(name: "zorpcore", events_count: 3)
    CannedExtractionClient.install(events: [poster_event(genres: ["Loops/#{carried.name}/FX"])])
    visit capture_path
    pick "poster.png"

    assert_selector ".hw-combobox__chip", text: "Loops"
    assert_selector ".hw-combobox__chip", text: carried.name
    assert_selector ".hw-combobox__chip", text: "FX"

    accept
    assert_published
    assert_equal ["Fx", "Loops", carried.name].sort, Event.sole.genre_list.sort
  end

  test "a slash run nothing vouches for stays the single genre the model returned" do
    CannedExtractionClient.install(events: [poster_event(genres: ["Loops/FX"])])
    visit capture_path
    pick "poster.png"

    assert_selector ".hw-combobox__chip", count: 1, text: "Loops/FX"
  end

  test "a genre already in the taxonomy is offered while typing" do
    genre(name: "zorpwave", events_count: 3)
    CannedExtractionClient.install(events: [poster_event(genres: [])])
    visit capture_path
    pick "poster.png"

    find(".capture-card [role=combobox]").send_keys("zorpw")
    find("[role=option]", text: /zorpwave/).click

    assert_selector ".hw-combobox__chip", text: /zorpwave/
  end

  test "taking a place suggestion is recorded as a normalisation, not a correction" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(place: "Zorpsaal Zorpwil")])
    visit capture_path
    pick "poster.png"

    find(".suggestions button", text: "Zorpsaal").click
    accept
    assert_published

    assert_predicate ExtractionFieldOutcome.find_by(field: "place"), :normalized?
  end

  test "a place typed over a suggestion is the contributor's own reading again" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(place: "Zorpsaal Zorpwil")])
    visit capture_path
    pick "poster.png"

    find(".suggestions button", text: "Zorpsaal").click
    type("place", "Zorpkeller")
    accept
    assert_published

    assert_predicate ExtractionFieldOutcome.find_by(field: "place"), :corrected?
  end

  test "the towns of the suggested venues are chips beside the locality field" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    place(name: "Zorpkeller", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(place: "Zorpsaal Zorpwil", locality: nil,
                                                         locality_evidence: nil, canton: nil)])
    visit capture_path
    pick "poster.png"

    towns = all(".suggestions button", text: "Zorpwil")
    assert_equal 1, towns.size

    towns.first.click
    assert_equal "Zorpwil", field_value("locality")
    assert_equal "BE", field_value("canton")
  end

  test "typing a town offers the ones the app already knows" do
    place(locality: "Zorpwil", canton: "BE")
    place(locality: "Zorpheim", canton: "LU")
    place(locality: "Flarnhausen", canton: "ZH")
    CannedExtractionClient.install(events: [poster_event(place: nil, place_evidence: nil,
                                                         locality: nil, locality_evidence: nil,
                                                         canton: nil)])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".suggestions"
    type("locality", "zorp")

    assert_selector ".suggestions button", text: "Zorpheim"
    assert_no_selector ".suggestions button", text: "Flarnhausen"

    find(".suggestions button", text: "Zorpheim").click
    assert_equal "Zorpheim", field_value("locality")
    assert_equal "LU", field_value("canton")
  end

  test "typing a venue offers the ones the app already knows" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "ZH")
    CannedExtractionClient.install(events: [poster_event(place: nil, place_evidence: nil,
                                                         locality: nil, locality_evidence: nil,
                                                         canton: nil)])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".suggestions"
    type("place", "zorps")

    assert_selector ".suggestions button", text: "Zorpsaal"
    assert_no_selector ".suggestions button", text: "Flarnhalle"

    find(".suggestions button", text: "Zorpsaal").click
    assert_equal "Zorpsaal", field_value("place")
    assert_equal "Zorpwil", field_value("locality")
    assert_equal "BE", field_value("canton")
  end

  test "taking a typed venue is recorded as a normalisation, not a correction" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(place: "Blorpwerk",
                                                         place_evidence: "Blorpwerk")])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".suggestions"
    type("place", "zorps")
    find(".suggestions button", text: "Zorpsaal").click
    accept
    assert_published

    assert_predicate ExtractionFieldOutcome.find_by(field: "place"), :normalized?
  end

  test "taking a town is recorded as a normalisation, not a correction" do
    place(name: "Zorpsaal", locality: "Flarnhausen", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(place: "Zorpsaal Halle",
                                                         place_evidence: "Zorpsaal Halle")])
    visit capture_path
    pick "poster.png"

    find(".suggestions button", text: "Flarnhausen").click
    accept
    assert_published

    assert_predicate ExtractionFieldOutcome.find_by(field: "locality"), :normalized?
  end

  test "a venue the app already carries reaches the card in its own spelling" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(place: "ZORPSAAL",
                                                         place_evidence: "ZORPSAAL",
                                                         locality: nil, locality_evidence: nil,
                                                         canton: nil)])
    visit capture_path
    pick "poster.png"

    assert_equal "Zorpsaal", field_value("place")
    assert_equal "Zorpwil", field_value("locality")
    assert_equal "BE", field_value("canton")

    accept
    assert_published

    assert_no_difference -> { Place.count } do
      assert_equal %w[BE Zorpsaal Zorpwil], Event.last.location_list.to_a.sort
    end
  end

  test "a venue the app already carries is not suggested back to the card" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    place(name: "Zorpsaal Keller", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_equal "Zorpsaal", field_value("place")
    assert_no_selector ".suggestions"

    type("locality", "zorpw")
    assert_selector ".suggestions button", text: "Zorpwil"
  end

  test "a town the app already carries reaches the card in its own spelling" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(locality: "ZORPWIL",
                                                         locality_evidence: "3000 ZORPWIL")])
    visit capture_path
    pick "poster.png"

    assert_equal "Zorpwil", field_value("locality")
    assert_equal "Zorpwil", find(".capture-card [name=proposed_locality]", visible: :all).value
    assert_selector ".capture-card", text: "3000 ZORPWIL"

    accept
    assert_published

    assert_predicate ExtractionFieldOutcome.find_by(field: "locality"), :unchanged?
    assert_equal ["Zorpwil"], Event.last.location_list.grep_v(/\A(BE|Zorpsaal)\z/)
  end

  test "a locality the app already knows fills the canton beside it" do
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_equal "BE", field_value("canton")
    type "locality", "Flarnhausen"

    assert_equal "AG", field_value("canton")
  end

  test "a locality nobody knows leaves the canton standing" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    type "locality", "Neuzorp"

    assert_equal "BE", field_value("canton")
  end

  test "a canton filled from the locality is recorded as a normalisation, not a correction" do
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    type "locality", "Flarnhausen"
    accept
    assert_published

    assert_predicate ExtractionFieldOutcome.find_by(field: "canton"), :normalized?
  end

  test "an event entered by hand publishes and lands back on the picker" do
    visit capture_path
    by_hand

    assert_selector "h1", text: copy("manual.title")
    assert_equal "", manual_value("title")

    manual_field("title").set("Zorp Fest")
    manual_field("date").set(show_date.to_s)
    manual_field("locality").set("Zorpwil")
    manual_field("canton").select("BE — Bern")

    assert_difference -> { Event.count } => 1 do
      find("#manual-event-form input[type=submit]").click
      assert_selector ".flash", text: I18n.t("capture.card.published", title: "Zorp Fest", locale: :de)
    end
    assert_selector ".capture-picker"
    assert_equal "Zorp Fest", Event.last.title
  end

  test "everything below the queue strip scrolls like a plain page" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"
    page.current_window.resize_to(390, 844)

    assert_operator rect(".capture-card .action-bar")["top"], :>, viewport_height

    scroll_to_bottom

    assert_operator page.evaluate_script("window.scrollY"), :>, 0
    assert_operator rect(".review-card__source")["bottom"], :<, 0
    assert_in_delta 0, rect(".capture-queue")["top"], 1
  end

  test "publishing brings the next card to rest under the strip" do
    CannedExtractionClient.install(events: [poster_event, matinee])
    visit capture_path
    pick "poster.png"
    page.current_window.resize_to(390, 844)
    scroll_to_bottom

    accept
    assert_selector ".capture-queue__tile[data-state='published']"

    assert_equal "Zorpcore Matinee", field_value("title")
    assert_in_delta rect(".capture-queue")["bottom"], rect(".capture-card")["top"], 2
  end

  test "the hand-entry page carries none of the review screen's furniture" do
    visit capture_path
    by_hand

    assert_no_selector ".review-card"
    assert_no_selector ".review-card__source"
    assert_no_selector ".capture-queue"
    assert_no_selector ".capture-card__reread"
    assert_no_selector ".drop-zone__item"
  end

  test "the hand-entry screen offers the venues and towns the app already knows" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "ZH")
    visit capture_path
    by_hand

    assert_no_selector ".suggestions"

    manual_field("place").set("zorps")
    find(".suggestions button", text: "Zorpsaal").click

    assert_equal "Zorpsaal", manual_value("place")
    assert_equal "Zorpwil", manual_value("locality")
    assert_equal "BE", manual_value("canton")

    manual_field("locality").set("flarn")
    find(".suggestions button", text: "Flarnhausen").click

    assert_equal "Flarnhausen", manual_value("locality")
    assert_equal "ZH", manual_value("canton")
  end

  test "a town typed out by hand on the hand-entry screen still moves the canton" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "ZH")
    visit capture_path
    by_hand

    manual_field("locality").set("flarn")
    find(".suggestions button", text: "Flarnhausen").click
    assert_equal "ZH", manual_value("canton")

    manual_field("locality").set("Zorpwil")
    manual_field("title").click

    assert_equal "BE", manual_value("canton")
  end

  test "a re-read appends a fresh card instead of replacing the one being disputed" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    mark "date"
    find(".capture-card__note").set("da steht der 21. August")
    reread

    assert_selector ".capture-card", count: 2, visible: :all
    assert_selector ".capture-queue__group", count: 2

    reported = CannedExtractionClient.corrections.compact.sole
    assert_equal %w[date], reported.fields
    assert_equal "da steht der 21. August", reported.note
  end

  test "a re-read with nothing marked is still a second look" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    reread
    assert_selector ".capture-card", count: 2, visible: :all

    assert_empty CannedExtractionClient.corrections.compact.sole.fields
  end

  test "a poster gets two re-reads and then says why there are no more" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    reread
    assert_selector ".capture-card", count: 2, visible: :all
    reread
    assert_selector ".capture-card", count: 3, visible: :all

    assert_selector ".capture-card__reread", text: copy("reread.spent")
    assert find(".capture-card .card-aside button[data-action='capture#reread']").disabled?
  end

  test "the re-read button sits with the controls it acts on, not in the action bar" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-card .card-aside button[data-action='capture#reread']"
    assert_no_selector ".capture-card .action-bar button[data-action='capture#reread']"
    assert_selector ".capture-card .action-bar > *", count: 2
  end

  test "a dropped card reports what the model had proposed" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    reject
    assert_published 0

    page.document.synchronize(errors: [Minitest::Assertion]) do
      assert_equal "Zorpsaal", ExtractionFieldOutcome.discarded.find_by(field: "place")&.proposed
    end
  end

  test "a refusal stays on its own card instead of taking the queue with it" do
    CannedExtractionClient.install(events: [poster_event(canton: nil)])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-card select[name=canton]"
    execute_script("document.querySelector('.capture-card [name=canton]').removeAttribute('required')")
    accept

    assert_selector ".capture-card__status--refused", text: copy("errors.incomplete")
    assert_empty Event.all
    assert_no_selector ".flash"
  end

  test "the last decision hands the screen back to the picker" do
    CannedExtractionClient.install(events: [poster_event, matinee])
    visit capture_path
    pick "poster.png"

    reject
    accept

    assert_published
    assert_selector ".capture-picker"
    assert_no_selector ".capture-card", visible: :all
    assert_no_selector ".capture-queue__tile"
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

  test "a locality corrected on one card reaches the siblings that read one of their own" do
    place(name: "Zorpwiler Rathaus", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(locality: "Us", locality_evidence: "Us", canton: "ZH"),
                                            matinee(locality: "Us", locality_evidence: "Us", canton: "ZH")])
    visit capture_path
    pick "poster.png"

    type "locality", "Zorpwil"
    reject
    assert_equal "Zorpcore Matinee", field_value("title")
    assert_equal "Zorpwil", field_value("locality")
    assert_equal "BE", field_value("canton")
  end

  test "a venue corrected on one card reaches the siblings that read one of their own" do
    CannedExtractionClient.install(events: [poster_event, matinee(place: "Zorpkeller", place_evidence: "Zorpkeller")])
    visit capture_path
    pick "poster.png"

    type "place", "Zorpwiler Rathaus"
    reject
    assert_equal "Zorpcore Matinee", field_value("title")
    assert_equal "Zorpwiler Rathaus", field_value("place")
  end

  test "a sibling the contributor answered first keeps its town when another is corrected" do
    CannedExtractionClient.install(events: [poster_event(locality: "Us", locality_evidence: "Us"),
                                            matinee(locality: "Us", locality_evidence: "Us")])
    visit capture_path
    pick "poster.png"

    jump_to 1
    type "locality", "Flarnhausen"
    jump_to 0
    type "locality", "Zorpwil"
    assert_equal "Zorpwil", field_value("locality")

    jump_to 1
    assert_equal "Zorpcore Matinee", field_value("title")
    assert_equal "Flarnhausen", field_value("locality")
  end

  test "a place typed on one input stays on it rather than reaching the next input's cards" do
    CannedExtractionClient.install(events: [poster_event(locality: nil, canton: nil)])
    visit capture_path
    pick "poster.png", "flyer.png"
    assert_selector ".capture-card", count: 2, visible: :all

    type "locality", "Zorpwil"
    reject
    assert_equal "", field_value("locality")
  end

  test "the strip states the whole batch from the moment it is sent" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png", "flyer.png"

    assert_selector ".capture-queue__group", count: 2
    assert_selector ".capture-queue__tile", count: 2
  end

  test "candidates off one input are one group in the strip" do
    CannedExtractionClient.install(events: [poster_event, matinee])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-queue__group", count: 1
    assert_selector ".capture-queue__group .capture-queue__tile", count: 2
    assert_no_selector ".capture-queue__tile[data-state=pending]"
  end

  test "an input that yields nothing still holds its place in the strip" do
    CannedExtractionClient.install(events: [])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-row", text: copy("row.nothing_found")
    assert_selector ".capture-queue__tile[data-state=failed]", count: 1
    assert_no_selector ".capture-queue__tile[data-state=pending]"
  end

  test "each decided tile carries the mark for its own outcome" do
    CannedExtractionClient.install(events: [poster_event, matinee, poster_event(title: "Zorpcore Spaet")])
    visit capture_path
    pick "poster.png"

    accept
    assert_selector ".capture-queue__tile[data-state=published] .ph-check-circle"
    reject
    assert_selector ".capture-queue__tile[data-state=dropped] .ph-x"
  end

  test "an input that came back with nothing does not wear a dropped card's mark" do
    CannedExtractionClient.install(events: [])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-queue__tile[data-state=failed] .ph-warning-circle"
    assert_no_selector ".capture-queue__tile .ph-x"
  end

  test "a tile stood up before its read carries the poster all the same" do
    CannedExtractionClient.install(events: [])
    visit capture_path
    pick "poster.png"

    assert_decoded ".capture-queue__tile img"
  end

  test "the tile names the input the row no longer does" do
    CannedExtractionClient.install(events: [])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-queue__tile[aria-label='poster.png']"
  end

  test "a failed extraction reaches the strip rather than only the rows list" do
    CannedExtractionClient.install(raises: "HTTP 503: upstream busy")
    visit capture_path
    paste "Zorpcore Nacht, Zorpsaal"

    assert_selector ".capture-row", text: copy("failures.provider_error")
    assert_selector ".capture-queue__tile[data-state=failed]", count: 1
  end

  test "the card names no source: the poster beside it already is one" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".capture-card__label"
    assert_no_selector ".capture-card", text: "poster.png"
  end

  test "a long source name stays on one line on the row that failed to read it" do
    CannedExtractionClient.install(raises: "HTTP 503: upstream busy")
    visit capture_path
    pick_as "Zorpcore-Nacht-im-Zorpsaal-Zorpwil-mit-Vorband-und-allem-Drum-und-Dran-final-v3.png"

    label = find(".capture-row__label")
    assert_equal "nowrap", label.style("white-space")["white-space"]
    assert_operator label.evaluate_script("this.scrollWidth"), :>, label.evaluate_script("this.clientWidth")
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

  test "the read button is dead until there is text to read" do
    visit capture_path
    assert read_disabled?

    type_text "Z"
    assert_not read_disabled?

    find(".capture-picker textarea").send_keys(:backspace)
    assert read_disabled?
  end

  test "an image on the clipboard is read like a picked poster" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    paste_image

    assert_equal "Zorpcore Nacht", field_value("title")
    assert_decoded ".capture-card:not([hidden]) .review-card__source img"
  end

  test "a pasted poster is named for the gesture on its tile" do
    CannedExtractionClient.install(events: [])
    visit capture_path
    paste_image

    assert_selector ".capture-queue__tile[aria-label='#{copy("row.pasted")}']"
  end

  test "a clipboard with no image on it says so rather than failing a row" do
    visit capture_path
    hold_on_clipboard clipboard_text
    paste_button.click

    assert_selector ".drop-zone__error", text: copy("picker.paste_empty")
    assert_selector ".capture-picker"
    assert_no_selector ".capture-row"
  end

  test "a declined paste says nothing at all" do
    visit capture_path
    hold_on_clipboard "async () => { throw new DOMException('denied', 'NotAllowedError') }"
    paste_button.click

    assert_no_selector ".drop-zone__error", visible: true
    assert_no_selector ".capture-row"
  end

  test "the refusal does not outlive the picker it was shown on" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    hold_on_clipboard clipboard_text
    paste_button.click
    assert_selector ".drop-zone__error"

    pick "poster.png"
    find("button[data-action='capture#startOver']").click

    assert_no_selector ".drop-zone__error", visible: true
  end

  test "an image pasted onto the picker is read without touching the button" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    paste_onto "document.body"
    settle_read

    assert_equal "Zorpcore Nacht", field_value("title")
  end

  test "a paste into the text field stays the text field's" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    paste_onto "document.querySelector('.capture-picker textarea')", text: "Zorpcore Nacht"

    assert_no_selector ".capture-row"
    assert_selector ".capture-picker"
  end

  test "a paste lands nowhere while cards are being decided" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    paste_onto "document.body"
    assert_selector ".capture-row", count: 1, visible: :all
  end

  test "the paste button is taken away where the clipboard cannot be read" do
    visit capture_path
    assert paste_button.visible?

    execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: undefined })
      Stimulus.getControllerForElementAndIdentifier(document.querySelector(".capture"), "capture").connect()
    JS

    assert_no_selector ".drop-zone__paste", visible: true
  end

  test "a file no browser can decode fails its own row and lets the rest of the pick land" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "broken.png", "poster.png"

    assert_selector ".capture-row", text: "broken.png"
    assert_selector ".capture-row", text: copy("failures.image_unsupported")
    assert_selector ".capture-card", count: 1, visible: :all
  end

  test "the input step is gone while cards are being decided, and start over brings it back" do
    CannedExtractionClient.install(events: [poster_event, matinee])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".capture-picker"
    assert_no_selector ".page-header", text: copy("picker.add_by_hand")
    reject
    find("button[data-action='capture#startOver']").click

    assert_selector ".capture-picker"
    assert_selector ".page-header", text: copy("picker.add_by_hand")
    assert_selector "h1", text: copy("title")
    assert_no_selector ".page-header", text: copy("review.hint")
    assert_no_selector ".capture-card", visible: :all
    assert_no_selector ".drop-zone__item"
    assert_no_selector ".capture-queue__tile"
  end

  test "the review step heads with how many events were found" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    assert_selector "h1", text: copy("title")

    pick "poster.png"
    assert_selector "h1", text: copy("review.title", count: 1)
    assert_no_selector "h1", text: copy("title")

    find("button[data-action='capture#startOver']").click
    assert_selector "h1", text: copy("title")

    CannedExtractionClient.install(events: [poster_event, matinee])
    pick "poster.png"
    assert_selector "h1", text: copy("review.title", count: 2)
  end

  test "a finished batch hands back a picker that reads another input" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"
    reject
    assert_selector ".capture-picker"

    paste "Zorpcore Matinee, Zorpsaal"

    assert_selector ".capture-card"
    assert_selector ".capture-row__excerpt", text: "Zorpcore Matinee, Zorpsaal"
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
    assert_no_selector ".capture-card", visible: :all
  end

  private

  def show_date = Date.current + 30

  def poster_event(**overrides)
    { title: "Zorpcore Nacht", date: show_date.to_s, date_evidence: "steht auf dem Plakat",
      time: "20 Uhr", time_evidence: "20 Uhr", place: "Zorpsaal", place_evidence: "Zorpsaal",
      locality: "Zorpwil", locality_evidence: "3000 Zorpwil", canton: "BE",
      genres: ["zorpcore"], source_url: nil }.merge(overrides)
  end

  def matinee(**overrides) = poster_event(title: "Zorpcore Matinee", **overrides)

  def type(field, value)
    find(".capture-card [name='#{field}']").set(value)
    find(".capture-card [name=title]").click
  end

  def pick(*names)
    find(".drop-zone__input", visible: :all).set(names.map { |name| file_fixture(name) })
    assert_selector ".capture-row", count: names.size, wait: 5, visible: :all
    assert_no_selector "[data-pending]", text: copy("row.pending"), wait: 5
  end

  def pick_as(name)
    path = Rails.root.join("tmp", name)
    FileUtils.cp(file_fixture("poster.png"), path)
    @staged_paths << path
    find(".drop-zone__input", visible: :all).set([path])
    assert_selector ".capture-row", count: 1, wait: 5
    assert_no_selector "[data-pending]", text: copy("row.pending"), wait: 5
  end

  def paste(text)
    type_text(text)
    read_text
  end

  def paste_button = find(".drop-zone__paste")

  def hold_on_clipboard(read)
    execute_script(<<~JS)
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { read: #{read} } })
    JS
  end

  def clipboard_image
    "async () => [new ClipboardItem({ 'image/png': #{poster_blob_js} })]"
  end

  def clipboard_text
    "async () => [new ClipboardItem({ 'text/plain': new Blob(['Zorpcore Nacht'], { type: 'text/plain' }) })]"
  end

  def poster_blob_js
    data = Base64.strict_encode64(file_fixture("poster.png").binread)
    "new Blob([Uint8Array.from(atob('#{data}'), (c) => c.charCodeAt(0))], { type: 'image/png' })"
  end

  def paste_image
    hold_on_clipboard clipboard_image
    paste_button.click
    settle_read
  end

  def paste_onto(target, text: nil)
    execute_script(<<~JS)
      const data = new DataTransfer()
      data.items.add(new File([#{poster_blob_js}], "poster.png", { type: "image/png" }))
      #{"data.setData('text/plain', #{text.to_json})" if text}
      #{target}.dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS
  end

  def settle_read
    assert_selector ".capture-row", count: 1, wait: 5
    assert_no_selector "[data-pending]", text: copy("row.pending"), wait: 5
  end

  def type_text(text) = find(".capture-picker textarea").set(text)

  def read_text = find("button[data-action='capture#readText']").click

  def by_hand = find(".page-header a[href='#{manual_capture_path}']").click

  def read_disabled? = find("button[data-action='capture#readText']").disabled?

  def accept = find(".capture-card .action-bar input[type=submit]").click

  def reject = find(".capture-card .action-bar button[data-action='capture#reject']").click

  def reread = find(".capture-card .card-aside button[data-action='capture#reread']").click

  def mark(field) = find(".capture-card__reread label.tag", text: copy("candidate.#{field}")).click

  def cite(quote) = I18n.t("shared.cite", locale: :de, quote: quote)

  def field_value(field) = find(".capture-card [name='#{field}']").value
  def field_type(field) = find(".capture-card [name='#{field}']")[:type]

  def manual_field(field) = find("#manual-event-form [name='#{field}']")
  def manual_value(field) = manual_field(field).value

  def assert_published(count = 1) = assert_selector(".flash", text: copy("queue.done", count: count))

  def scroll_to_bottom = execute_script("window.scrollTo(0, document.body.scrollHeight)")

  def viewport_height = page.evaluate_script("window.innerHeight")

  def rect(selector) = find(selector).evaluate_script("this.getBoundingClientRect().toJSON()")

  def jump_to(index)
    assert_selector ".capture-queue__tile", minimum: index + 1
    all(".capture-queue__tile")[index].click
  end

  def add_genre(name)
    input = find(".capture-card [role=combobox]")
    input.send_keys(name)
    assert_no_selector "[role=option]"
    input.send_keys(:enter)
  end

  def copy(key, **args) = I18n.t("capture.#{key}", locale: :de, **args)

  def assert_decoded(selector)
    find(selector)
    page.document.synchronize(errors: [Minitest::Assertion]) do
      assert_operator evaluate_script("document.querySelector('#{selector}').naturalWidth"), :>, 0
    end
  end
end
