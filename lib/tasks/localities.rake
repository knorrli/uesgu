namespace :localities do
  desc "Re-derive the locality table from the venue registry, the captured places " \
       "and the location tags. Runs after every sweep (Scrapers::Sweep); this is the " \
       "hand crank — a fresh database, or a registry edit you don't want to wait a " \
       "night for. Idempotent."
  task reconcile: :environment do
    Locality.reconcile!
    settled = Locality.canonicals.where.not(canton: nil).count
    puts "#{Locality.canonicals.count} localities (#{settled} with a canton), " \
         "#{Locality.aliased.count} merged."
  end
end
