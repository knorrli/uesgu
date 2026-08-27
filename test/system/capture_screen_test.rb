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
    # Normalised by EventCapture::Clock on the way here, not by the model, which
    # said "20 Uhr" — proof the card went through the real extraction path.
    assert_equal "20:00", field_value("time")

    assert_difference -> { Event.count } => 1, -> { Place.count } => 1 do
      accept
      assert_published
    end
    assert_equal "Zorpwil", Place.last.locality
    assert_selector ".capture-picker"
  end

  # Asserts the type and not the height: the trap is mobile Safari's control metrics
  # for a date input (see app/views/captures/_candidate.html.erb), and headless Chrome
  # lines a date up with a text field either way — so a height assertion here would
  # pass on the one browser that never had the problem.
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

  # The residual failure after the evidence rule is cited-but-wrong, and the quote is
  # the only thing on the card that separates a locality read off a postcode from one
  # read off an artist's origin code.
  test "each field carries the text the model quoted as its source" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_selector ".review-card__cite", text: cite("3000 Zorpwil")
    assert_selector ".review-card__cite", text: cite("Zorpsaal")
    assert_selector ".review-card__cite", text: cite("steht auf dem Plakat")
  end

  # A quote under an empty field reads as a value being withheld. The model can cite a
  # place it then returned as null, so the card keys the quote to the value, not to the
  # evidence string.
  test "a field the model left empty shows no quote" do
    CannedExtractionClient.install(events: [poster_event(place: nil)])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".review-card__cite", text: cite("Zorpsaal")
    assert_selector ".review-card__cite", text: cite("3000 Zorpwil")
  end

  # An origin code the model can quote back survives the evidence rule and is
  # well-formed, so nothing refuses it: the human's edit is the only record that it
  # was wrong (see ExtractionFieldOutcome).
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

  # Two candidates off one poster are the same picture twice, so without a number the
  # strip reads as one thumbnail rendered twice rather than as two events to decide on.
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

  # A phone is where posters are captured, and the gem's alternative to the dropdown is
  # a modal dialog that covers the card from mid-screen down and — once the software
  # keyboard takes the bottom of it — shows fewer options than the dropdown does.
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

  # The vocabulary is a few hundred options and a batch is N posters x M events, so a
  # copy inside every card grows with both — and with the taxonomy. One copy lives in
  # the page and is lent to whichever card is open.
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

  # The combobox hides an option it already holds in the field, and a card is lent a
  # list that knows nothing of what it has picked.
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

  # A tap on a chip targets the chip, and inside a wrapping <label> that is a click on
  # the label — which the browser forwards to the input, defeating the remover. What
  # the markup has to do instead: app/views/captures/_candidate.html.erb.
  test "tapping a genre chip's remover on a phone takes the genre off" do
    CannedExtractionClient.install(events: [poster_event(genres: %w[zorpcore flarncore])])
    visit capture_path
    pick "poster.png"
    page.current_window.resize_to(390, 844)

    find(".hw-combobox__chip", text: "zorpcore").find(".hw-combobox__chip__remover").click

    assert_no_selector ".hw-combobox__chip", text: "zorpcore"
    assert_selector ".hw-combobox__chip", text: "flarncore"
  end

  # The field used to be a comma-joined text input, so a poster naming its genres with
  # any other separator became one genre. A chip per genre is what makes that visible.
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

  # Observed on a real poster: six genres came back as one string. The chips make the
  # run visible as a single genre, and the taxonomy is what says it is several (see
  # EventCapture::Genres).
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
    # "Fx", not "FX": a genre nobody carries is stored under the display spelling
    # Genre.canonicalize_names gives it, exactly as a hand-typed one is.
    assert_equal ["Fx", "Loops", carried.name].sort, Event.sole.genre_list.sort
  end

  # The other half of the rule, and the one that keeps a genre name with a slash in it
  # from being minted as two that do not exist.
  test "a slash run nothing vouches for stays the single genre the model returned" do
    CannedExtractionClient.install(events: [poster_event(genres: ["Loops/FX"])])
    visit capture_path
    pick "poster.png"

    assert_selector ".hw-combobox__chip", count: 1, text: "Loops/FX"
  end

  # The suggestions are the point of the combobox: a genre we already carry should be
  # picked rather than respelt, which is what keeps the taxonomy from growing a fourth
  # spelling of the same thing.
  test "a genre already in the taxonomy is offered while typing" do
    genre(name: "zorpwave", events_count: 3)
    CannedExtractionClient.install(events: [poster_event(genres: [])])
    visit capture_path
    pick "poster.png"

    find(".capture-card [role=combobox]").send_keys("zorpw")
    find("[role=option]", text: /zorpwave/).click

    assert_selector ".hw-combobox__chip", text: /zorpwave/
  end

  # Tapping a suggestion swaps the poster's spelling for the registry's. Counted as a
  # correction it would inflate the one number a prompt edit is judged on.
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

  # Nothing is offered until a contributor types, so the towns of the venues being
  # suggested are the only ranking the field has before they do.
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

  # Typing is the only way to the towns no venue on this poster points at, and the
  # matching is the app's own: iOS Safari draws an <input list> in the strip above the
  # keyboard and gives that strip to its own address autofill, so a datalist is offered
  # to nobody there.
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

  # Tapping a town is taking the app's spelling over the poster's, exactly as tapping a
  # venue is — and counted as a correction it would inflate the one number a prompt
  # edit is judged on. A venue the fingerprint reaches is folded before the card
  # renders and brings its own town with it, so the case left for a human is the
  # NEAR-match: suggested, scored, and nothing applied until someone taps.
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

  # The venue half of the same rule as the town below: the app's spelling reaches the
  # card, so a contributor confirms the name the publish will actually file under.
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

  # Typing at the end is not incidental: the row it fills is one of the two that just
  # went empty, and dropping that row outright would take the long tail of towns with it.
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

  # The spelling half of the same thing, and the reason the test above had to move off
  # it: the card is handed the town's own spelling, so there is no correction for a
  # contributor to make and none to record. That the model shouted is an extraction
  # issue (see EventCapture::Normalizer), not a human's edit.
  test "a town the app already carries reaches the card in its own spelling" do
    place(name: "Zorpsaal", locality: "Zorpwil", canton: "BE")
    CannedExtractionClient.install(events: [poster_event(locality: "ZORPWIL",
                                                         locality_evidence: "3000 ZORPWIL")])
    visit capture_path
    pick "poster.png"

    assert_equal "Zorpwil", field_value("locality")
    assert_equal "Zorpwil", find(".capture-card [name=proposed_locality]", visible: :all).value
    # The citation is the one thing that stays verbatim: it is a quote of the poster,
    # and one edited to match our spelling could no longer be checked against it.
    assert_selector ".capture-card", text: "3000 ZORPWIL"

    accept
    assert_published

    assert_predicate ExtractionFieldOutcome.find_by(field: "locality"), :unchanged?
    assert_equal ["Zorpwil"], Event.last.location_list.grep_v(/\A(BE|Zorpsaal)\z/)
  end

  # A venue nobody knows is exactly the case that mints a fresh spelling, and it is the
  # case with no ranking to render — so the words are what say the suggestions exist.
  test "with no venue to suggest, the locality field says the suggestions are there" do
    CannedExtractionClient.install(events: [poster_event(place: nil, place_evidence: nil)])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".suggestions"
    assert_selector ".capture-card", text: copy("candidate.locality_hint")
  end

  # The canton is computed from the locality once, server-side, at extraction — so a
  # locality changed on the card has to bring its own (see Locality).
  test "a locality the app already knows fills the canton beside it" do
    place(name: "Flarnhalle", locality: "Flarnhausen", canton: "AG")
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_equal "BE", field_value("canton")
    type "locality", "Flarnhausen"

    assert_equal "AG", field_value("canton")
  end

  # Clearing it would throw away the model's own postcode reading, which is the reason
  # the field is still asked for at all.
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

  # No poster, no paste, no model call — a page of its own, and the same publish.
  test "an event entered by hand publishes and lands back on the picker" do
    visit capture_path
    by_hand

    assert_selector "h1", text: copy("manual.title")
    assert_equal "", manual_value("title")

    manual_field("title").set("Zorp Fest")
    manual_field("date").set(show_date.to_s)
    manual_field("locality").set("Zorpwil")
    manual_field("canton").select("Bern")

    assert_difference -> { Event.count } => 1 do
      find("#manual-event-form input[type=submit]").click
      assert_selector ".flash", text: I18n.t("capture.card.published", title: "Zorp Fest", locale: :de)
    end
    assert_selector ".capture-picker"
    assert_equal "Zorp Fest", Event.last.title
  end

  # An absence test on purpose: the card's frame is shared markup one caller away, and
  # this is the only thing standing between it and creeping back onto a screen with no
  # source to compare against.
  test "the hand-entry page carries none of the review screen's furniture" do
    visit capture_path
    by_hand

    assert_no_selector ".review-card"
    assert_no_selector ".review-card__source"
    assert_no_selector ".capture-queue"
    assert_no_selector ".capture-card__reread"
    assert_no_selector ".drop-zone__item"
    # The viewport is bounded only so a poster can hold still above the fields.
    assert_no_selector "html.capture-reviewing", visible: :all
  end

  # The third option beside publish and drop. The flags are what make it more than a
  # coin flip — see EventCapture::Correction for why an identical request is not one.
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

  # Every re-read is a paid third-party call, so the budget is per INPUT: the cards a
  # re-read produces do not arrive with one of their own.
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

  # The bar carries the two decisions that END the card. Asking for another go leaves
  # it in play, so the button belongs with the checkboxes and the note it sends.
  test "the re-read button sits with the controls it acts on, not in the action bar" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-card .card-aside button[data-action='capture#reread']"
    assert_no_selector ".capture-card .action-bar button[data-action='capture#reread']"
    assert_selector ".capture-card .action-bar > *", count: 2
  end

  # A drop never reaches the server on its own, and it is the read worth the most:
  # the contributor looked at the card and threw all of it away.
  test "a dropped card reports what the model had proposed" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    reject
    assert_published 0

    # The record is fire-and-forget, so it lands after the card is already gone.
    page.document.synchronize(errors: [Minitest::Assertion]) do
      assert_equal "Zorpsaal", ExtractionFieldOutcome.discarded.find_by(field: "place")&.proposed
    end
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
    assert_no_selector ".flash"
  end

  # The strip is the only receipt for what published, and going back to the picker
  # throws it away — so what replaces it has to say how much went live.
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

  # The strip outlives the cards, and the only thing it is scanned for is what has
  # already been answered — so each answer has to be its own mark, not a shared one.
  test "each decided tile carries the mark for its own outcome" do
    CannedExtractionClient.install(events: [poster_event, matinee, poster_event(title: "Zorpcore Spaet")])
    visit capture_path
    pick "poster.png"

    accept
    assert_selector ".capture-queue__tile[data-state=published] .ph-check-circle"
    reject
    assert_selector ".capture-queue__tile[data-state=dropped] .ph-x"
  end

  # An input nothing came back from was judged by nobody, so it may not wear the mark
  # of a card someone threw away.
  test "an input that came back with nothing does not wear a dropped card's mark" do
    CannedExtractionClient.install(events: [])
    visit capture_path
    pick "poster.png"

    assert_selector ".capture-queue__tile[data-state=failed] .ph-warning-circle"
    assert_no_selector ".capture-queue__tile .ph-x"
  end

  # The tile is stood up before the downscale that gives it a picture, so it is the one
  # place the poster can go missing; a card's own tile is built once the blob is held.
  test "a tile stood up before its read carries the poster all the same" do
    CannedExtractionClient.install(events: [])
    visit capture_path
    pick "poster.png"

    assert_decoded ".capture-queue__tile img"
  end

  # The row stops repeating it while the read is in flight, so the strip is where a
  # contributor still finds out which input a tile stands for.
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

  # Picking files ends on a dialog closing and dropping them ends on a drag; typing ends
  # on nothing, which is why the text field is the only entry point with a button.
  test "the read button is dead until there is text to read" do
    visit capture_path
    assert read_disabled?

    type_text "Z"
    assert_not read_disabled?

    find(".capture-picker textarea").send_keys(:backspace)
    assert read_disabled?
  end

  # Nothing is held back to be sent later, so a file no browser can decode has to fail
  # where it lands — on its own row, named — rather than as a chip that never went.
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
    reject
    find("button[data-action='capture#startOver']").click

    assert_selector ".capture-picker"
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

  # The whole reason nothing is staged: there is no need to assemble a batch when
  # deciding one hands the picker straight back for the next.
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

  # Far enough out that the candidate is never past.
  def show_date = Date.current + 30

  # The shape EventCapture::Prompt::SCHEMA asks the model for. `date_evidence` cites
  # no date on purpose: YearResolver would otherwise recompute the year from it and
  # move the date this test asserts on.
  def poster_event(**overrides)
    { title: "Zorpcore Nacht", date: show_date.to_s, date_evidence: "steht auf dem Plakat",
      time: "20 Uhr", time_evidence: "20 Uhr", place: "Zorpsaal", place_evidence: "Zorpsaal",
      locality: "Zorpwil", locality_evidence: "3000 Zorpwil", canton: "BE",
      genres: ["zorpcore"], source_url: nil }.merge(overrides)
  end

  def matinee(**overrides) = poster_event(title: "Zorpcore Matinee", **overrides)

  # Blurred on purpose: the carry hangs off `change`, which a text field fires when it
  # is left, not on every keystroke.
  def type(field, value)
    find(".capture-card [name='#{field}']").set(value)
    find(".capture-card [name=title]").click
  end

  # The picker is hidden synchronously in the change handler — leavePicker() is the
  # first statement of readImages, before the first await — so waiting on it being gone
  # waits for nothing, and the line after would inherit the whole read inside one
  # default_max_wait_time. Waiting on the pending copy clearing absorbs the canvas
  # encode, the upload and the extraction here instead. The TEXT, not the element: an
  # undecodable file keeps its row and overwrites that copy with the reason.
  def pick(*names)
    find(".drop-zone__input", visible: :all).set(names.map { |name| file_fixture(name) })
    assert_selector ".capture-row", count: names.size, wait: 5
    assert_no_selector "[data-pending]", text: copy("row.pending"), wait: 5
  end

  # A filename is the one source label that is not truncated on the way in, so the
  # overflow case needs a real file carrying a real long name.
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

  def type_text(text) = find(".capture-picker textarea").set(text)

  def read_text = find("button[data-action='capture#readText']").click

  def by_hand = find(".capture-by-hand a").click

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

  # Accepting the last card in a queue hands the screen straight back to the picker, so
  # the tile that said it published is gone before an assertion could look for it. The
  # flash is what outlives that, and waiting on it is also what holds a test back until
  # the publish has landed.
  def assert_published(count = 1) = assert_selector(".flash", text: copy("queue.done", count: count))

  # The strip is the only way onto a card that has not been decided yet. Waits for the
  # tile to exist: reads land one at a time, and `all` does not wait for a count.
  def jump_to(index)
    assert_selector ".capture-queue__tile", minimum: index + 1
    all(".capture-queue__tile")[index].click
  end

  # A name nothing matches empties the list, and waiting for that is what makes the
  # Enter land after the filter has run rather than before it, without a sleep.
  def add_genre(name)
    input = find(".capture-card [role=combobox]")
    input.send_keys(name)
    assert_no_selector "[role=option]"
    input.send_keys(:enter)
  end

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
