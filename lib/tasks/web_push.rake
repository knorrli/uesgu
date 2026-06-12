namespace :web_push do
  desc "Generate a VAPID keypair for Web Push; print env-var lines to copy"
  task generate_keys: :environment do
    key = WebPush.generate_key

    puts "# Web Push VAPID keypair — set these as environment variables."
    puts "# Keep the private key secret (Render env var / .env, never committed)."
    puts "VAPID_PUBLIC_KEY=#{key.public_key}"
    puts "VAPID_PRIVATE_KEY=#{key.private_key}"
  end
end
