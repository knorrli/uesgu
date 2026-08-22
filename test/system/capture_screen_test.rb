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
    assert_selector ".capture-queue__tile[data-state=published]"

    locality = ExtractionFieldOutcome.find_by(field: "locality")
    assert_predicate locality, :corrected?
    assert_equal "Us", locality.proposed
    assert_equal "Zorpwil", locality.accepted
  end

  test "the genres the model read arrive as chips and publish as they are" do
    CannedExtractionClient.install(events: [poster_event(genres: %w[zorpcore flarncore])])
    visit capture_path
    pick "poster.png"

    assert_selector ".hw-combobox__chip", text: "zorpcore"
    assert_selector ".hw-combobox__chip", text: "flarncore"

    accept
    assert_selector ".capture-queue__tile[data-state=published]"
    assert_equal %w[Flarncore Zorpcore], Event.sole.genre_list.sort
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
    assert_selector ".capture-queue__tile[data-state=published]"
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
    assert_selector ".capture-queue__tile[data-state=published]"
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
    assert_selector ".capture-queue__tile[data-state=published]"

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
    assert_selector ".capture-queue__tile[data-state=published]"

    assert_predicate ExtractionFieldOutcome.find_by(field: "place"), :corrected?
  end

  # The datalist behind the field shows nothing until you type, so the towns of the
  # venues being suggested are the only ranking the field has (see #154).
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
    assert_selector ".capture-queue__tile[data-state=published]"

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
    assert_selector ".capture-queue__tile[data-state=published]"

    assert_no_difference -> { Place.count } do
      assert_equal %w[BE Zorpsaal Zorpwil], Event.last.location_list.to_a.sort
    end
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
    assert_selector ".capture-queue__tile[data-state=published]"

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
    assert_selector ".capture-queue__tile[data-state=published]"

    assert_predicate ExtractionFieldOutcome.find_by(field: "canton"), :normalized?
  end

  # No poster, no paste, no model call — and still the same card, the same queue and
  # the same publish.
  test "an event entered by hand becomes an empty card and publishes like any other" do
    visit capture_path
    find("button[data-action='capture#stageBlank']").click
    assert_selector ".drop-zone__item"
    commit

    assert_selector ".capture-card"
    assert_equal "", field_value("title")
    assert_equal "", field_value("locality")
    # No poster to show, so the pane says why it is empty rather than looking broken.
    assert_selector ".review-card__source", text: I18n.t("capture.staging.by_hand", locale: :de)

    type "title", "Zorp Fest"
    type "date", show_date.to_s
    type "locality", "Zorpwil"
    find(".capture-card [name=canton]").select("Bern")

    assert_difference -> { Event.count } => 1 do
      accept
      assert_selector ".capture-queue__tile[data-state=published]"
    end
    assert_equal "Zorp Fest", Event.last.title
  end

  test "a hand-entered event stages alongside a poster and commits with it" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    stage "poster.png"
    find("button[data-action='capture#stageBlank']").click
    assert_selector ".drop-zone__item", count: 2
    commit

    assert_selector ".capture-card", count: 2, visible: :all
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
    assert find(".capture-card .action-bar button[data-action='capture#reread']").disabled?
  end

  # There is no input to read again, so offering it would be a button that cannot work.
  test "a hand-entered card is not offered a re-read" do
    visit capture_path
    find("button[data-action='capture#stageBlank']").click
    assert_selector ".drop-zone__item"
    commit

    assert_selector ".capture-card"
    assert_no_selector ".capture-card .action-bar button[data-action='capture#reread']"
    assert_no_selector ".capture-card__reread"
  end

  # A drop never reaches the server on its own, and it is the read worth the most:
  # the contributor looked at the card and threw all of it away.
  test "a dropped card reports what the model had proposed" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    reject
    assert_selector ".capture-queue__tile[data-state=dropped]"

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
    stage "poster.png"
    stage_text "Zorpcore Nacht, Zorpsaal"
    commit
    assert_selector ".capture-card", count: 2, visible: :all

    type "locality", "Zorpwil"
    reject
    assert_equal "", field_value("locality")
  end

  test "the strip states the whole batch from the moment it is sent" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    stage "poster.png"
    stage_text "Zorpcore Matinee, Zorpsaal"
    commit

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

  test "a long source name stays on one line while its row is still reading" do
    CannedExtractionClient.install(raises: "HTTP 503: upstream busy")
    visit capture_path
    stage_as "Zorpcore-Nacht-im-Zorpsaal-Zorpwil-mit-Vorband-und-allem-Drum-und-Dran-final-v3.png"
    commit

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

  test "an unreadable file is caught at staging and never joins the committed batch" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    stage "broken.png", "poster.png"

    assert_selector ".drop-zone__item[data-state=undecodable]", text: "broken.png"
    assert_selector ".drop-zone__item[data-state=undecodable]", text: copy("failures.image_unsupported")
    commit
    assert_selector ".capture-card", count: 1, visible: :all
    assert_no_selector ".capture-row", text: copy("failures.image_unsupported")
  end

  test "posters and a pasted text commit as one batch" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    stage "poster.png"
    stage_text "Zorpcore Matinee, Zorpsaal"

    assert_no_selector ".capture-row"
    commit
    assert_selector ".capture-card", count: 2, visible: :all
  end

  test "a staged item can be removed before the batch is sent" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    stage "poster.png"
    stage_text "Zorpcore Matinee, Zorpsaal"

    all(".drop-zone__remove").first.click
    assert_selector ".drop-zone__item", count: 1
    commit
    assert_selector ".capture-card", count: 1, visible: :all
    assert_selector ".capture-row__excerpt", text: "Zorpcore Matinee, Zorpsaal"
  end

  test "the input step is gone while cards are being decided, and start over brings it back" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    pick "poster.png"

    assert_no_selector ".capture-picker"
    reject
    find("button[data-action='capture#startOver']").click

    assert_selector ".capture-picker"
    assert_no_selector ".capture-card", visible: :all
    assert_no_selector ".drop-zone__item"
    assert_no_selector ".capture-queue__tile"
  end

  test "nothing is sent until the batch is committed" do
    CannedExtractionClient.install(events: [poster_event])
    visit capture_path
    stage "poster.png"

    assert_no_selector ".capture-row", visible: :all
    assert_no_selector ".capture-card", visible: :all
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
      time: "20 Uhr", place: "Zorpsaal", place_evidence: "Zorpsaal", locality: "Zorpwil",
      locality_evidence: "3000 Zorpwil", canton: "BE", genres: ["zorpcore"],
      source_url: nil }.merge(overrides)
  end

  def matinee(**overrides) = poster_event(title: "Zorpcore Matinee", **overrides)

  # Blurred on purpose: the carry hangs off `change`, which a text field fires when it
  # is left, not on every keystroke.
  def type(field, value)
    find(".capture-card [name='#{field}']").set(value)
    find(".capture-card [name=title]").click
  end

  # Staging is silent, so every helper that stages waits for the item to appear before
  # the next step: without it a commit can fire before an async downscale has landed.
  def stage(*names)
    find(".drop-zone__input", visible: :all).set(names.map { |name| file_fixture(name) })
    assert_selector ".drop-zone__item", count: names.size, wait: 5
  end

  def stage_text(text)
    staged = all(".drop-zone__item").size
    find(".capture-picker textarea").set(text)
    find("button[data-action='capture#stageText']").click
    assert_selector ".drop-zone__item", count: staged + 1
  end

  def commit = find("button[data-action='capture#commit']").click

  # A filename is the one source label that is not truncated on the way in, so the
  # overflow case needs a real file carrying a real long name.
  def stage_as(name)
    path = Rails.root.join("tmp", name)
    FileUtils.cp(file_fixture("poster.png"), path)
    @staged_paths << path
    find(".drop-zone__input", visible: :all).set([path])
    assert_selector ".drop-zone__item", wait: 5
  end

  def pick(*names)
    stage(*names)
    commit
  end

  def paste(text)
    stage_text(text)
    commit
  end

  def accept = find(".capture-card .action-bar input[type=submit]").click

  def reject = find(".capture-card .action-bar button[data-action='capture#reject']").click

  def reread = find(".capture-card .action-bar button[data-action='capture#reread']").click

  def mark(field) = find(".capture-card__reread label.tag", text: copy("candidate.#{field}")).click

  def cite(quote) = I18n.t("shared.cite", locale: :de, quote: quote)

  def field_value(field) = find(".capture-card [name='#{field}']").value

  # The genre combobox fetches its options as you type, and a name nothing matches
  # empties the list — waiting for that is what makes the Enter land after the
  # response rather than before it, without a sleep.
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
