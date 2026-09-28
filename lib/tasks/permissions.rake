namespace :permissions do
  desc "Give every account still flagged as a contributor the capture permission. Idempotent; " \
       "run once after the permissions column is deployed, before the contributor column is dropped."
  task import_contributors: :environment do
    imported = User.where(contributor: true).reject { |user| user.permissions.include?("capture") }
    imported.each { |user| user.update!(permissions: user.permissions + ["capture"]) }
    puts "#{imported.size} contributor(s) given the capture permission."
  end
end
