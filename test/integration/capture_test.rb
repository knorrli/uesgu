require "db_test_helper"

# The capture funnel end to end: the screen exists only for contributors, one
# extraction per request replaces its own row, and nothing is written before the
# human submits. Synthetic place names; the registry is read live.
class CaptureTest < ActionDispatch::IntegrationTest
  # Stands in for the extraction service — the provider itself is covered in
  # EventCapture::ExtractorTest.
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

  test "a blank card needs no model call, and carries no attempt to be judged on" do
    sign_in_as user(contributor: true)

    assert_no_difference -> { ExtractionAttempt.count } do
      post blank_capture_path, params: { row_id: "abc" }, as: :turbo_stream
    end

    assert_response :success
    assert_select "turbo-stream[target=capture-row-abc]"
    assert_match(/capture-card/, response.body)
  end

  test "a blank card publishes through the same path as an extracted one" do
    sign_in_as user(contributor: true)

    assert_difference -> { Event.count } => 1 do
      post capture_path, params: { title: "Zorp Fest", date: "2026-09-01", locality: "Zorpwil",
                                   canton: "BE" }, as: :turbo_stream
    end

    assert_equal "Zorp Fest", Event.last.title
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

    post blank_capture_path, params: { row_id: "abc" }, as: :turbo_stream

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

  # The card posts the report; the extractor is what has to receive it, because the
  # prompt is the only thing that makes a second read differ from the first.
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

  # A DOM id is interpolated from it, so anything else must not reach the markup.
  test "extract ignores a row id that is not a plain token" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate])) do
      post extract_capture_path, params: { row_id: '"><script>x</script>', text: "..." },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_no_match "<script>x</script>", response.body
  end

  # An adapter failure and a provider failure are the same shape, and the screen
  # owns the copy for both — the service only ever returns a symbol.
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
                                 locality: "Zorpwil", canton: "BE", place: "Zorpsaal" }

    assert_response :success
    assert_equal ["Kept"], Event.pluck(:title)
    assert_match 'target="capture-row-abc-0-status"', response.body
    assert_match I18n.t("capture.card.published", title: "Kept", locale: :en), response.body
  end

  # The card still holds the contributor's edits, so the response addresses the status
  # region rather than re-rendering fields over the top of them.
  test "a refusal lands on the card that caused it and writes nothing" do
    sign_in_as user(contributor: true, locale: "en")

    post capture_path, params: { card_id: "capture-row-abc-0", title: "No canton",
                                 date: "2026-09-01", locality: "Zorpwil", canton: "" }

    assert_response :unprocessable_entity
    assert_match 'target="capture-row-abc-0-status"', response.body
    assert_match I18n.t("capture.errors.incomplete", locale: :en), response.body
    assert_empty Event.all
  end

  # The card posts no link and this endpoint is reachable directly, so a url arriving
  # anyway is not a value of the event.
  test "a url posted past the card is ignored, not published" do
    sign_in_as user(contributor: true, locale: "en")

    post capture_path, params: { card_id: "capture-row-abc-1", title: "Unlinked",
                                 date: "2026-09-02", locality: "Zorpwil", canton: "BE",
                                 url: "https://zorp.example/poster" }

    assert_response :success
    assert_nil Event.sole.url
  end

  test "create ignores a card id that is not a plain token" do
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: '"><script>x</script>', title: "Kept",
                                 date: "2026-09-01", locality: "Zorpwil", canton: "BE" }

    assert_no_match "<script>x</script>", response.body
  end

  test "a candidate with no fields at all is a refusal, not a 500" do
    sign_in_as user(contributor: true)

    post capture_path
    assert_response :unprocessable_entity
    assert_empty Event.all
  end

  test "create splits comma-separated genres onto the event" do
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: "capture-row-abc-0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE", genres: "Zorpwave, Flarncore" }

    assert_equal %w[Flarncore Zorpwave], Event.sole.genre_list.sort
  end

  # An 8MB cap applied after `read` is not a cap: this endpoint is reachable
  # directly, and the client-side downscale is not a control.
  test "an oversize upload is refused before its bytes are read" do
    sign_in_as user(contributor: true, locale: "en")
    oversize = Rack::Test::UploadedFile.new(
      StringIO.new("x" * (EventCapture::Adapters::Image::LIMIT + 1)), "image/png",
      original_filename: "big.png"
    )

    # Adapters::Image.call is what pulls the bytes in, so the guard works only if it
    # is never reached. (Extractor.call always runs — it passes a failure through.)
    EventCapture::Adapters::Image.stub(:call, ->(_) { flunk "read the upload before capping it" }) do
      post extract_capture_path, params: { row_id: "abc123", image: oversize },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_match ERB::Util.html_escape(I18n.t("capture.failures.image_too_large", locale: :en)), response.body
  end

  # The corrections are the only evidence of a confidently wrong value: nothing
  # refuses "Us" as a locality, so without the diff the read records as clean.
  test "publishing records what the human changed against what the model proposed" do
    attempt = ExtractionAttempt.create!(status: :ok, medium: "image")
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: "capture-row-abc-0", attempt_token: attempt.capture_token,
                                 candidate_index: "0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE", time: "20:00",
                                 proposed_title: "Kept", proposed_date: "2026-09-01",
                                 proposed_locality: "Us", proposed_canton: "BE" }

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
                                 candidate_index: "0" }

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

  # A forged or stale id is the client's to send, so it may cost the row and nothing
  # else — never the event.
  test "a forged attempt token costs the record, not the publish" do
    sign_in_as user(contributor: true)

    post capture_path, params: { card_id: "capture-row-abc-0", attempt_token: "not-a-signed-id",
                                 candidate_index: "0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE" }

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
    # Compared by what it resolves to: the token carries its own expiry, so two of
    # them for the same attempt are not the same string.
    token = css_select("input[name=attempt_token]").first["value"]
    assert_equal attempt, ExtractionAttempt.find_by_capture_token(token)
    assert_select "input[name=?][value=?]", "candidate_index", "0"
  end

  # Neither pair has a quote per field: the model is asked for no time evidence, so what
  # it quoted for the date is all Zeit has (see EventCapture::Prompt), and the canton is
  # computed from the locality rather than read off the poster (see
  # EventCapture::Normalizer). A town chip fills both fields too, so confining either
  # line to one column would claim less than the card knows.
  test "a quote that settled a pair of fields is attached to the whole row" do
    place(name: "Zorpsaal", locality: "Flarnhausen", canton: "BE")
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate(place: "Zorpsaal Halle",
                                                      date_evidence: "SA 12. SEPT",
                                                      locality_evidence: "3000 Zorpwil")])) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_select ".capture-card__when + .field-group__attached .review-card__cite"
    assert_select ".capture-card__where + .field-group__attached .review-card__cite"
    assert_select ".capture-card__where + .field-group__attached .suggestions .chip",
                  text: "Flarnhausen"
    assert_select ".capture-card__where .field-group", false
    assert_select ".capture-card__when .field-group", false
  end

  # A date already gone is a remark about the date, and a line of its own between two
  # fields belongs to neither of them.
  test "the warning about a past date hangs off the date it is about" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate(date: Date.current - 1)])) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    assert_select ".capture-card__when + .field-group__attached .capture-card__warning",
                  text: I18n.t("capture.candidate.past")
  end

  # The `for`/id wiring the phone behaviour rests on — a label that wraps the field
  # instead reopens it on every tap (app/views/captures/_candidate.html.erb). The id is
  # asserted literally because the gem's fallback is a random uuid, which would satisfy
  # a `for`-matches-id check while changing on every render.
  test "the genre field is named by a label that does not wrap it" do
    sign_in_as user(contributor: true)

    stub_extraction(extraction(candidates: [candidate])) do
      post extract_capture_path, params: { row_id: "abc123" },
                                 headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    input = css_select(".capture-card__genres input.hw-combobox__input").sole
    assert_equal "capture-row-abc123-0-genres", input["id"]
    assert_select "label[for=?]", input["id"], text: I18n.t("capture.candidate.genres")
    assert_select ".capture-card__genres dialog.hw-combobox__dialog"
    assert_select "label .capture-card__genres", count: 0
  end

  # The taxonomy is offered so an existing genre is picked rather than respelt, but a
  # genre we ignore, hide or block is not something to put in front of a contributor.
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
                                 locality: "Zorpwil", canton: "BE" }

    assert_response :forbidden
    assert_empty Event.all
  end
end
