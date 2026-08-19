namespace :places do
  desc "Report captured places the venue taxonomy has since absorbed. A captured " \
       "venue that graduates to a placed consume row must lose its Place row in " \
       "the same PR, or one name has two identities. Read-only; exits nonzero on drift."
  task drift: :environment do
    shadowed = Place.shadowed
    if shadowed.empty?
      puts "No captured place collides with the venue registry."
      next
    end

    shadowed.each do |place|
      puts "  #{place.name} (#{place.locality}, #{place.canton}) — now a registry venue; delete Place ##{place.id}"
    end
    abort "#{shadowed.size} captured place(s) shadowed by the registry"
  end
end
