require "db_test_helper"

class CaptureTest < ActionDispatch::IntegrationTest
  def stub_extraction(extraction, &)
    EventCapture::Extractor.stub(:call, ->(**) { extraction }, &)
  end

  def candidate(**overrides)
    EventCapture::Candidate.new(**{ title: "Zorp Fest", date: Date.new(2026, 9, 1), time: "20:00",
                                    place: "Zorpsaal", locality: "Zorpwil", canton: "BE" }.merge(overrides))
  end

  def extraction(candidates: [], code: nil, error: nil)
    EventCapture::Extractor::Extraction.new(candidates: candidates, code: code, error: error)
  end

  test "the hand-entry page needs no model call, and carries no attempt to be judged on" do
    sign_in_as user(contributor: true)

    assert_no_difference -> { ExtractionAttempt.count } do
      get manual_capture_path
    end

    assert_response :success
    assert_select "form#manual-event-form input[name=title]"
  end

  test "the hand-entry page publishes through the same path as a card and lands back on the picker" do
    sign_in_as user(contributor: true, locale: "en")

    assert_difference -> { Event.count } => 1 do
      post capture_path, params: { title: "Zorp Fest", date: "2026-09-01", locality: "Zorpwil",
                                   canton: "BE" }
    end

    assert_redirected_to capture_path
    assert_equal I18n.t("capture.card.published", title: "Zorp Fest", locale: :en), flash[:notice]
    assert_equal "Zorp Fest", Event.last.title
  end

  test "a refusal comes back as the page with what was typed still in it" do
    sign_in_as user(contributor: true, locale: "en")

    post capture_path, params: { title: "No canton", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "" }

    assert_response :unprocessable_entity
    assert_match I18n.t("capture.errors.incomplete", locale: :en), response.body
    assert_select "input[name=title][value=?]", "No canton"
    assert_select "input[name=locality][value=?]", "Zorpwil"
    assert_empty Event.all
  end

  test "a duplicate comes back as the page with the matches to answer" do
    sign_in_as user(contributor: true, locale: "en")
    already_listed

    assert_no_difference -> { Event.count } do
      post capture_path, params: { title: "Zorp Fest", date: "2026-09-01", locality: "Zorpwil",
                                   canton: "BE", place: "Zorpsaal" }
    end

    assert_response :unprocessable_entity
    assert_select "button[form=manual-event-form][name=matched_event_id]"
    assert_select "input[name=title][value=?]", "Zorp Fest"
  end

  test "publishing from the page records no field outcome" do
    sign_in_as user(contributor: true)

    assert_no_difference -> { ExtractionFieldOutcome.count } do
      post capture_path, params: { title: "Zorp Fest", date: "2026-09-01", locality: "Zorpwil",
                                   canton: "BE" }
    end
  end

  test "the subtitle the model read is offered as the event's description" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate(subtitle: "message: incomplete",
                                                      subtitle_evidence: "message: incomplete")])) do
      post extract_capture_path, params: { text: "Zorp Fest", row_id: "abc" }, as: :turbo_stream
    end

    assert_select "input[name=description][value=?]", "message: incomplete"
  end

  test "a published card carries the description through" do
    sign_in_as user(contributor: true)

    post capture_path, params: { title: "Zorp Fest", date: "2026-09-01", locality: "Zorpwil",
                                 canton: "BE", description: "message: incomplete" }, as: :turbo_stream

    assert_equal "message: incomplete", Event.last.description
  end

  test "entering by hand is closed to accounts without the capability" do
    sign_in_as user

    get manual_capture_path

    assert_response :forbidden
  end

  test "the screen is closed to accounts without the capability" do
    sign_in_as user
    get capture_path

    assert_response :forbidden
  end

  test "the screen requires an account at all" do
    get capture_path

    assert_redirected_to new_session_path
  end

  test "a contributor gets the picker" do
    sign_in_as user(contributor: true)
    get capture_path

    assert_response :success
    assert_select "input[type=file]"
  end

  test "the nav links to capture only for contributors" do
    sign_in_as user(contributor: true)
    get root_path
    assert_select "a[href=?]", capture_path

    sign_in_as user
    get root_path
    assert_select "a[href=?]", capture_path, count: 0
  end

  test "extract replaces the input's own row with its candidates" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate, candidate(title: "Zorp Fest II")])) do
      post extract_capture_path, params: { row_id: "abc123", label: "poster.jpg", text: "..." },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_match 'target="capture-row-abc123"', response.body
    assert_match "Zorp Fest II", response.body
  end

  test "a re-read carries the marked fields and the note into the extraction" do
    sign_in_as user(contributor: true)
    seen = nil

    EventCapture::Extractor.stub(:call, ->(**args) { seen = args[:correction]; extraction }) do
      post extract_capture_path,
           params: { row_id: "abc123", text: "...", reread: "1", wrong: "date,place",
                     note: "the poster says 21 August" },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_equal %w[date place], seen.fields
    assert_equal "the poster says 21 August", seen.note
  end

  test "a first read reaches the extractor with nothing to correct" do
    sign_in_as user(contributor: true)
    seen = :unset

    EventCapture::Extractor.stub(:call, ->(**args) { seen = args[:correction]; extraction }) do
      post extract_capture_path, params: { row_id: "abc123", text: "..." },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_nil seen
  end

  test "extract ignores a row id that is not a plain token" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate])) do
      post extract_capture_path, params: { row_id: '"><script>x</script>', text: "..." },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_no_match "<script>x</script>", response.body
  end

  test "extract renders the contributor-facing copy for a failure code" do
    sign_in_as user(contributor: true, locale: "en")

    stub_extraction(extraction(code: :image_too_large, error: "image is over 8MB")) do
      post extract_capture_path, params: { row_id: "abc123", text: "..." },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_match I18n.t("capture.failures.image_too_large", locale: :en), response.body
    assert_no_match(/image is over 8MB/, response.body)
  end

  test "an unreadable upload is one row, not a dead batch" do
    sign_in_as user(contributor: true, locale: "en")
    file = Rack::Test::UploadedFile.new(StringIO.new("not an image"), "image/png", original_filename: "x.png")

    post extract_capture_path, params: { row_id: "abc123", image: file },
                               headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match ERB::Util.html_escape(I18n.t("capture.failures.image_unsupported", locale: :en)), response.body
  end

  test "create publishes the one candidate on the card" do
    sign_in_as user(contributor: true, locale: "en")

    post capture_path, params: { card_id: "capture-row-abc-0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE", place: "Zorpsaal" }, as: :turbo_stream

    assert_response :success
    assert_equal ["Kept"], Event.pluck(:title)
    assert_match 'target="capture-row-abc-0-status"', response.body
    assert_match I18n.t("capture.card.published", title: "Kept", locale: :en), response.body
  end

  test "a refusal lands on the card that caused it and writes nothing" do
    sign_in_as user(contributor: true, locale: "en")

    post capture_path, params: { card_id: "capture-row-abc-0", title: "No canton",
                                 date: "2026-09-01", locality: "Zorpwil", canton: "" }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_match 'target="capture-row-abc-0-status"', response.body
    assert_match I18n.t("capture.errors.incomplete", locale: :en), response.body
    assert_empty Event.all
  end

  test "a url posted past the card is ignored, not published" do
    sign_in_as user(contributor: true, locale: "en")

    post capture_path, params: { card_id: "capture-row-abc-1", title: "Unlinked",
                                 date: "2026-09-02", locality: "Zorpwil", canton: "BE",
                                 url: "https://zorp.example/poster" }, as: :turbo_stream

    assert_response :success
    assert_nil Event.sole.url
  end

  test "create ignores a card id that is not a plain token" do
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: '"><script>x</script>', title: "Kept",
                                 date: "2026-09-01", locality: "Zorpwil", canton: "BE" }, as: :turbo_stream

    assert_no_match "<script>x</script>", response.body
  end

  test "a candidate with no fields at all is a refusal, not a 500" do
    sign_in_as user(contributor: true)

    post capture_path, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_empty Event.all
  end

  test "create splits comma-separated genres onto the event" do
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: "capture-row-abc-0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE", genres: "Zorpwave, Flarncore" }, as: :turbo_stream

    assert_equal %w[Flarncore Zorpwave], Event.sole.genre_list.sort
  end

  test "an oversize upload is refused before its bytes are read" do
    sign_in_as user(contributor: true, locale: "en")
    oversize = Rack::Test::UploadedFile.new(
      StringIO.new("x" * (EventCapture::Adapters::Image::LIMIT + 1)), "image/png",
      original_filename: "big.png"
    )

    EventCapture::Adapters::Image.stub(:call, ->(_) { flunk "read the upload before capping it" }) do
      post extract_capture_path, params: { row_id: "abc123", image: oversize },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_match ERB::Util.html_escape(I18n.t("capture.failures.image_too_large", locale: :en)), response.body
  end

  test "publishing records what the human changed against what the model proposed" do
    attempt = ExtractionAttempt.create!(status: :ok, medium: "image")
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: "capture-row-abc-0", attempt_token: attempt.capture_token,
                                 candidate_index: "0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE", time: "20:00",
                                 proposed_title: "Kept", proposed_date: "2026-09-01",
                                 proposed_locality: "Us", proposed_canton: "BE" }, as: :turbo_stream

    outcomes = attempt.field_outcomes.index_by(&:field)
    assert_predicate outcomes.fetch("locality"), :corrected?
    assert_equal "Us", outcomes.fetch("locality").proposed
    assert_predicate outcomes.fetch("time"), :supplied?
    assert_predicate outcomes.fetch("date"), :unchanged?
  end

  test "a refused publish records no decision, because none was made" do
    attempt = ExtractionAttempt.create!(status: :ok, medium: "image")
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: "capture-row-abc-0", attempt_token: attempt.capture_token,
                                 candidate_index: "0" }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_empty attempt.field_outcomes
  end

  test "dropping a candidate records what it had proposed" do
    attempt = ExtractionAttempt.create!(status: :ok, medium: "image")
    sign_in_as user(contributor: true)

    post drop_capture_path, params: { attempt_token: attempt.capture_token, candidate_index: "1",
                                      proposed_title: "Zorp Fest", proposed_place: "Zorpsaal" }

    assert_response :no_content
    assert attempt.field_outcomes.all?(&:discarded?)
    assert_equal "Zorpsaal", attempt.field_outcomes.find_by(field: "place").proposed
    assert_equal [1], attempt.field_outcomes.pluck(:candidate_index).uniq
  end

  test "dropping is closed to accounts without the capability" do
    attempt = ExtractionAttempt.create!(status: :ok, medium: "image")
    sign_in_as user

    post drop_capture_path, params: { attempt_token: attempt.capture_token, candidate_index: "0" }

    assert_response :forbidden
    assert_empty attempt.field_outcomes
  end

  test "a forged attempt token costs the record, not the publish" do
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: "capture-row-abc-0", attempt_token: "not-a-signed-id",
                                 candidate_index: "0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE" }, as: :turbo_stream

    assert_equal "Kept", Event.sole.title
    assert_empty ExtractionFieldOutcome.all
  end

  test "the card carries the model's proposal alongside the editable value" do
    sign_in_as user(contributor: true)
    attempt = ExtractionAttempt.create!(status: :ok, medium: "image")

    stub_extraction(extraction(candidates: [candidate(locality: "Us")]).with(attempt_token: attempt.capture_token)) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_select "input[name=?][value=?]", "proposed_locality", "Us"
    token = css_select("input[name=attempt_token]").first["value"]
    assert_equal attempt, ExtractionAttempt.find_by_capture_token(token)
    assert_select "input[name=?][value=?]", "candidate_index", "0"
  end

  test "a quote that settled a pair of fields is attached to the whole row" do
    place(name: "Zorpsaal", locality: "Flarnhausen", canton: "BE")
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate(place: "Zorpsaal Halle",
                                                      locality_evidence: "3000 Zorpwil")])) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_select ".capture-fields__where + .field-group__attached .review-card__cite"
    assert_select ".capture-fields__where + .field-group__attached .suggestions .chip",
                  text: "Flarnhausen"
    assert_select ".capture-fields__where .field-group", false
  end

  test "date and time each carry the line they were read from" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate(date_evidence: "SA 12. SEPT",
                                                      time_evidence: "Türöffnung 20:00")])) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    cites = css_select ".capture-fields__when > .field-group .review-card__cite"
    assert_equal 2, cites.size
    assert_match "SA 12. SEPT", cites.first.text
    assert_match "Türöffnung 20:00", cites.last.text
  end

  test "the warning about a past date is the last line of the date and time row" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate(date: Date.current - 1)])) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_select ".capture-fields__when > .field-group", 2
    assert_select ".capture-fields__when > :last-child.capture-fields__warning",
                  text: I18n.t("capture.candidate.past")
    assert_select ".field-group .capture-fields__warning", false
  end

  test "the genre field is named by a label that does not wrap it" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate])) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    input = css_select(".genre-combobox input.hw-combobox__input").sole
    assert_equal "capture-row-abc123-0-genres", input["id"]
    assert_select "label[for=?]", input["id"], text: I18n.t("capture.candidate.genres")
    assert_select ".genre-combobox dialog.hw-combobox__dialog"
    assert_select "label .genre-combobox", count: 0
  end

  test "the offered genres cover what is in use and leave the dispositioned out" do
    wanted = genre(name: "zorpwave", events_count: 3)
    genre(name: "zorpwave-blocked", events_count: 3).block!
    genre(name: "zorpwave-unused", events_count: 0)
    sign_in_as user(contributor: true)

    get capture_path

    assert_select "template [role=option][data-value=?]", wanted.name
    assert_select "template [role=option][data-value=?]", "zorpwave-blocked", count: 0
    assert_select "template [role=option][data-value=?]", "zorpwave-unused", count: 0
  end

  test "a chip is rendered for a genre the taxonomy has never seen" do
    sign_in_as user(contributor: true)

    post genre_chips_capture_path, params: { combobox_values: "dubtronica, zorpcore" },
                                   headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :success
    assert_match "dubtronica", response.body
    assert_match "zorpcore", response.body
  end

  test "the genre chips endpoint is closed to accounts without the capability" do
    sign_in_as user

    post genre_chips_capture_path, params: { combobox_values: "zorp" }

    assert_response :forbidden
  end

  test "publishing is closed to accounts without the capability" do
    sign_in_as user

    post capture_path, params: { card_id: "capture-row-abc-0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE" }, as: :turbo_stream

    assert_response :forbidden
    assert_empty Event.all
  end
  def already_listed(**overrides)
    event(**{ title: "Zorp Fest", start_date: Date.new(2026, 9, 1),
              location_list: %w[Zorpsaal Zorpwil BE] }.merge(overrides))
  end

  def publish(**params)
    post capture_path, params: { card_id: "capture-row-abc-0", title: "Zorp Fest",
                                 date: "2026-09-01", locality: "Zorpwil", canton: "BE",
                                 place: "Zorpsaal" }.merge(params), as: :turbo_stream
  end

  test "a card whose show we already carry offers it on the card" do
    sign_in_as user(contributor: true)
    match = already_listed

    stub_extraction(extraction(candidates: [candidate])) do
      post extract_capture_path, params: { text: "Zorp Fest", row_id: "abc" }, as: :turbo_stream
    end

    assert_select ".capture-card__matches" do
      assert_select "button[name=matched_event_id][value=?]", match.id.to_s
      assert_select "button[name=acknowledged]"
    end
  end

  test "publishing over a match writes nothing and asks instead" do
    sign_in_as user(contributor: true)
    already_listed

    assert_no_difference -> { Event.count } do
      publish
    end

    assert_response :unprocessable_entity
    assert_select ".capture-card__matches"
  end

  test "the question posts back to the card's own form" do
    sign_in_as user(contributor: true)
    already_listed
    publish

    assert_select "button[form=?]", "capture-row-abc-0-form", minimum: 2
  end

  test "answering with the match folds the capture onto it and hands over what it read" do
    sign_in_as user(contributor: true)
    match = already_listed(description: nil)

    assert_difference -> { Event.count } => 1 do
      publish(matched_event_id: match.id, description: "Support: Zorpband", genres: "zorpcore")
    end

    assert_response :success
    assert_equal match.id, Event.last.canonical_event_id
    assert_equal "Support: Zorpband", match.reload.description
    assert_includes match.genre_list.map(&:downcase), "zorpcore"
  end

  test "answering that it is a different event publishes it" do
    sign_in_as user(contributor: true)
    already_listed

    assert_difference -> { Event.count } => 1 do
      publish(acknowledged: "1")
    end

    assert_response :success
    assert_nil Event.last.canonical_event_id
  end
end
