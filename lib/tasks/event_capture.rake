namespace :event_capture do
  desc "Extract event candidates from images or pasted text (- for stdin; creates no event)"
  task :extract, [:target] => :environment do |_task, args|
    targets = [args[:target], *args.extras].compact_blank
    abort 'usage: bin/rails "event_capture:extract[poster.jpg|-]"' if targets.empty?
    abort EventCapture::Extractor::UNCONFIGURED unless EventCaptureConfig.configured?

    puts "model: #{EventCaptureConfig.model}   today: #{Time.zone.today}"

    failures = targets.count { |target| report(target, EventCapture::Extractor.call(input: input_for(target))) }

    abort "\n#{failures} of #{targets.size} input(s) failed" if failures.positive?
  end

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
      puts "  #{extraction.detail}" if extraction.detail
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
    puts "      cites  date: #{candidate.date_evidence.inspect}  place: #{candidate.place_evidence.inspect}" \
         "  locality: #{candidate.locality_evidence.inspect}"
    puts "      genres #{candidate.genres.join(', ')}" if candidate.genres.any?
    puts "      url    #{candidate.source_url}" if candidate.source_url
    puts "      ⚠ #{candidate.issues.join(', ')} — model said #{candidate.raw.inspect}" if candidate.issues.any?
  end
end
