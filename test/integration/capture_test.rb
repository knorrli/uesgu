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

  # The door only exists for accounts that were given the capability.
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

  test "create publishes only the candidates that were kept" do
    sign_in_as user(contributor: true)

    post capture_path, params: { candidates: {
      a: { accept: "1", title: "Kept", date: "2026-09-01", locality: "Zorpwil", canton: "BE", place: "Zorpsaal" },
      b: { accept: "0", title: "Dropped", date: "2026-09-02", locality: "Zorpwil", canton: "BE" }
    } }

    assert_redirected_to root_path
    assert_equal ["Kept"], Event.pluck(:title)
  end

  test "create writes nothing when everything was dropped" do
    sign_in_as user(contributor: true)

    post capture_path, params: { candidates: {
      a: { accept: "0", title: "Dropped", date: "2026-09-01", locality: "Zorpwil", canton: "BE" }
    } }

    assert_redirected_to capture_path
    assert_empty Event.all
  end

  test "create splits comma-separated genres onto the event" do
    sign_in_as user(contributor: true)

    post capture_path, params: { candidates: {
      a: { accept: "1", title: "Kept", date: "2026-09-01", locality: "Zorpwil", canton: "BE",
           genres: "Zorpwave, Flarncore" }
    } }

    assert_equal %w[Flarncore Zorpwave], Event.sole.genre_list.sort
  end

  test "publishing is closed to accounts without the capability" do
    sign_in_as user

    post capture_path, params: { candidates: {
      a: { accept: "1", title: "Kept", date: "2026-09-01", locality: "Zorpwil", canton: "BE" }
    } }

    assert_response :forbidden
    assert_empty Event.all
  end
end
