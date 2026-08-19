namespace :event_capture do
  # The console entry point for the capture funnel, built BEFORE any UI so the
  # verify screen (#106) is written against a real contract rather than a guessed
  # one. Runs a target through its adapter and the extractor, then prints what the
  # verify screen would receive; writes nothing to the database and stores no image.
  #
  #   bin/rails "event_capture:extract[poster.jpg]"
  #   bin/rails "event_capture:extract[poster.jpg,screenshot.png]"
  #   pbpaste | bin/rails "event_capture:extract[-]"
  #
  # Needs INFOMANIAK_API_TOKEN + INFOMANIAK_PRODUCT_ID (see
  # config/initializers/event_capture.rb).
  desc "Extract event candidates from images or pasted text (- for stdin; read-only, persists nothing)"
  task :extract, [:target] => :environment do |_task, args|
    targets = [args[:target], *args.extras].compact_blank
    abort 'usage: bin/rails "event_capture:extract[poster.jpg|-]"' if targets.empty?
    abort EventCapture::Extractor::UNCONFIGURED unless EventCaptureConfig.configured?

    puts "model: #{EventCaptureConfig.model}   today: #{Time.zone.today}"

    failures = targets.count { |target| report(target, EventCapture::Extractor.call(input: input_for(target))) }

    abort "\n#{failures} of #{targets.size} input(s) failed" if failures.positive?
  end

  # Which adapter a target gets is decided by the target, not by a flag — the same
  # doors-into-one-funnel shape the UI will have. A file is an image if its bytes
  # say so and text otherwise; "-" is a paste.
  def input_for(target)
    return EventCapture::Adapters::Text.call($stdin.read) if target == "-"

    abort "no such file: #{target}" unless File.exist?(target)

    data = File.binread(target)
    return EventCapture::Adapters::Image.call(data) if EventCapture::Adapters::Image.media_type_for(data)

    EventCapture::Adapters::Text.call(data)
  end

  def report(target, extraction)
    puts "\n#{target}"

    unless extraction.ok?
      puts "  FAILED (#{extraction.code}): #{extraction.error}"
      return true
    end

    puts format("  %d candidate(s)  %.1fs  %d in / %d out tokens",
                extraction.candidates.size, extraction.elapsed,
                extraction.input_tokens, extraction.output_tokens)
    extraction.candidates.each_with_index { |candidate, i| print_candidate(candidate, i) }
    false
  end

  def print_candidate(candidate, index)
    puts "  [#{index}] #{candidate.title || '(no title)'}"
    puts "      when   #{candidate.date || '—'} #{candidate.time}#{' (past)' if candidate.past?}"
    puts "      where  #{candidate.place || '—'} · #{candidate.locality || '—'} · #{candidate.canton || '—'}"
    puts "      cites  date: #{candidate.date_evidence.inspect}  place: #{candidate.place_evidence.inspect}"
    puts "      genres #{candidate.genres.join(', ')}" if candidate.genres.any?
    puts "      url    #{candidate.source_url}" if candidate.source_url
    # The interesting column: what the model claimed and we refused, and why.
    puts "      ⚠ #{candidate.issues.join(', ')} — model said #{candidate.raw.inspect}" if candidate.issues.any?
  end
end
