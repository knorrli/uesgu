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

  # The card in front of the contributor is the only thing that can carry the
  # reason, and it still holds their edits — so the response addresses the status
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

  # Two candidates off one poster carry the same source_url. Per card there is no
  # batch to pre-check against: the second one accepted simply meets the unique
  # index, which is the honest answer — by then the first one IS an existing event.
  test "a link already published reads as an existing event" do
    sign_in_as user(contributor: true, locale: "en")
    event(url: "https://zorp.example/poster", title: "Scraped")

    post capture_path, params: { card_id: "capture-row-abc-1", title: "Clashes",
                                 date: "2026-09-02", locality: "Zorpwil", canton: "BE",
                                 url: "https://zorp.example/poster" }

    assert_response :unprocessable_entity
    assert_match I18n.t("capture.errors.duplicate", locale: :en), response.body
    assert_equal ["Scraped"], Event.pluck(:title)
  end

  # A DOM id is interpolated from it, so anything else must not reach the markup.
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

  test "publishing is closed to accounts without the capability" do
    sign_in_as user

    post capture_path, params: { card_id: "capture-row-abc-0", title: "Kept", date: "2026-09-01",
                                 locality: "Zorpwil", canton: "BE" }

    assert_response :forbidden
    assert_empty Event.all
  end
end
