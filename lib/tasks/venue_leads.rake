namespace :venue_leads do
  desc "Nominate captured places that keep hosting shows into the venue-lead inbox. " \
       "Runs after every sweep (Scrapers::Sweep); this is the hand crank. Idempotent."
  task from_captures: :environment do
    leads = CapturedVenueLeads.refresh!
    puts "#{leads.size} captured place(s) nominated " \
         "(#{CapturedVenueLeads::THRESHOLD}+ events, not in config/venues.yml)."
    leads.each { |lead| puts "  #{lead[:venue]} (#{lead[:locality]}, #{lead[:canton]}) — #{lead[:event_count]}×" }
  end
end
