namespace :event_capture do
  # The console entry point for the extraction service, built BEFORE any UI so the
  # verify screen (#106) is written against a real contract rather than a guessed
  # one. Sends the image to Infomaniak and prints what the funnel would hand the
  # verify screen; writes nothing to the database.
  #
  #   bin/rails "event_capture:extract[poster.jpg]"
  #   bin/rails "event_capture:extract[poster.jpg,screenshot.png]"
  #
  # Needs INFOMANIAK_API_TOKEN + INFOMANIAK_PRODUCT_ID (see
  # config/initializers/event_capture.rb).
  desc "Extract event candidates from image files (read-only; prints, persists nothing)"
  task :extract, [:path] => :environment do |_task, args|
    paths = [args[:path], *args.extras].compact_blank
    abort 'usage: bin/rails "event_capture:extract[poster.jpg,...]"' if paths.empty?
    abort EventCapture::Extractor::UNCONFIGURED unless EventCaptureConfig.configured?

    puts "model: #{EventCaptureConfig.model}   today: #{Time.zone.today}"

    failures = paths.count do |path|
      abort "no such file: #{path}" unless File.exist?(path)

      extraction = EventCapture::Extractor.call(image_data: File.binread(path), media_type: media_type_for(path))
      puts "\n#{File.basename(path)}"

      unless extraction.ok?
        puts "  FAILED: #{extraction.error}"
        next true
      end

      puts format("  %d candidate(s)  %.1fs  %d in / %d out tokens",
                  extraction.candidates.size, extraction.elapsed,
                  extraction.input_tokens, extraction.output_tokens)
      extraction.candidates.each_with_index { |candidate, i| print_candidate(candidate, i) }
      false
    end

    abort "\n#{failures} of #{paths.size} image(s) failed" if failures.positive?
  end

  # Only what a poster or a chat screenshot actually arrives as. An unknown
  # extension aborts rather than guessing: the media type goes into the data URL,
  # and a wrong one gets read as an unreadable image rather than as an error.
  MEDIA_TYPES = { ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
                  ".webp" => "image/webp", ".gif" => "image/gif" }.freeze

  def media_type_for(path)
    MEDIA_TYPES.fetch(File.extname(path).downcase) do
      abort "unsupported image type: #{File.extname(path).presence || path} (#{MEDIA_TYPES.keys.join(' ')})"
    end
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
