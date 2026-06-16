# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_06_16_100200) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "pg_catalog.plpgsql"

  create_table "event_saves", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "event_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_event_saves_on_event_id"
    t.index ["user_id", "event_id"], name: "index_event_saves_on_user_id_and_event_id", unique: true
    t.index ["user_id"], name: "index_event_saves_on_user_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "title", null: false
    t.string "subtitle"
    t.date "start_date", null: false
    t.datetime "start_time"
    t.string "url", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "hidden", default: false, null: false
    t.datetime "cancelled_at"
    t.bigint "created_in_scrape_run_id"
    t.datetime "dismissed_at"
    t.jsonb "overridden_fields", default: [], null: false
    t.index ["created_in_scrape_run_id"], name: "index_events_on_created_in_scrape_run_id"
    t.index ["dismissed_at"], name: "index_events_on_dismissed_at"
    t.index ["hidden"], name: "index_events_on_hidden"
    t.index ["start_date"], name: "index_events_on_start_date"
    t.index ["url"], name: "index_events_on_url", unique: true
  end

  create_table "genres", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "ignored_at"
    t.integer "events_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "hidden_at"
    t.datetime "blocked_at"
    t.virtual "fingerprint", type: :string, as: "regexp_replace(translate(replace(replace(lower((name)::text), '&'::text, 'and'::text), '''n'''::text, 'and'::text), 'äöüàâéèêëïîôûç'::text, 'aouaaeeeeiiouc'::text), '[^a-z0-9]'::text, ''::text, 'g'::text)", stored: true
    t.bigint "canonical_id"
    t.index "lower((name)::text)", name: "index_genres_on_lower_name", unique: true
    t.index ["blocked_at"], name: "index_genres_on_blocked_at"
    t.index ["canonical_id"], name: "index_genres_on_canonical_id"
    t.index ["fingerprint"], name: "index_genres_on_fingerprint", unique: true
    t.index ["hidden_at"], name: "index_genres_on_hidden_at"
    t.index ["ignored_at"], name: "index_genres_on_ignored_at"
    t.check_constraint "canonical_id IS NULL OR canonical_id <> id", name: "genres_canonical_not_self"
  end

  create_table "genres_styles", id: false, force: :cascade do |t|
    t.bigint "genre_id", null: false
    t.bigint "style_id", null: false
    t.index ["genre_id", "style_id"], name: "index_genres_styles_on_genre_id_and_style_id", unique: true
    t.index ["style_id"], name: "index_genres_styles_on_style_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.string "code", null: false
    t.bigint "created_by_id", null: false
    t.bigint "redeemed_by_id"
    t.datetime "redeemed_at"
    t.string "note"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_invitations_on_code", unique: true
    t.index ["created_by_id"], name: "index_invitations_on_created_by_id"
    t.index ["redeemed_by_id"], name: "index_invitations_on_redeemed_by_id"
  end

  create_table "notification_rules", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.boolean "enabled", default: true, null: false
    t.string "cadence", default: "weekly", null: false
    t.integer "weekday"
    t.integer "monthday"
    t.integer "time_of_day", default: 1080, null: false
    t.datetime "last_fired_at"
    t.jsonb "filter", default: {}, null: false
    t.boolean "notify_push", default: true, null: false
    t.boolean "notify_email", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "track_favorites", default: false, null: false
    t.index ["enabled", "cadence"], name: "index_notification_rules_on_enabled_and_cadence"
    t.index ["user_id"], name: "index_notification_rules_on_user_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "period_start", null: false
    t.datetime "period_end", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "notification_rule_id"
    t.jsonb "event_ids", default: [], null: false
    t.string "title"
    t.index ["notification_rule_id"], name: "index_notifications_on_notification_rule_id"
    t.index ["user_id", "period_end"], name: "index_notifications_on_user_id_and_period_end"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "endpoint", null: false
    t.string "p256dh_key", null: false
    t.string "auth_key", null: false
    t.string "user_agent"
    t.datetime "last_pushed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "scrape_results", force: :cascade do |t|
    t.bigint "scrape_run_id", null: false
    t.string "scraper", null: false
    t.string "status", null: false
    t.datetime "started_at"
    t.integer "duration_ms"
    t.integer "rows_seen", default: 0, null: false
    t.integer "created_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.string "error_class"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "unchanged_count", default: 0, null: false
    t.index ["scrape_run_id", "scraper"], name: "index_scrape_results_on_scrape_run_id_and_scraper"
    t.index ["scrape_run_id"], name: "index_scrape_results_on_scrape_run_id"
    t.index ["scraper"], name: "index_scrape_results_on_scraper"
  end

  create_table "scrape_runs", force: :cascade do |t|
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.string "status", default: "running", null: false
    t.integer "scrapers_total", default: 0, null: false
    t.integer "scrapers_ok", default: 0, null: false
    t.integer "scrapers_empty", default: 0, null: false
    t.integer "scrapers_failed", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_scrape_runs_on_started_at"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "styles", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "taggings", force: :cascade do |t|
    t.bigint "tag_id"
    t.string "taggable_type"
    t.bigint "taggable_id"
    t.string "tagger_type"
    t.bigint "tagger_id"
    t.string "context", limit: 128
    t.datetime "created_at", precision: nil
    t.index ["context"], name: "index_taggings_on_context"
    t.index ["tag_id", "taggable_id", "taggable_type", "context", "tagger_id", "tagger_type"], name: "taggings_idx", unique: true
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_id", "taggable_type", "context"], name: "taggings_taggable_context_idx"
    t.index ["taggable_id", "taggable_type", "tagger_id", "context"], name: "taggings_idy"
    t.index ["taggable_id"], name: "index_taggings_on_taggable_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
    t.index ["taggable_type"], name: "index_taggings_on_taggable_type"
    t.index ["tagger_id", "tagger_type"], name: "index_taggings_on_tagger_id_and_tagger_type"
    t.index ["tagger_id"], name: "index_taggings_on_tagger_id"
    t.index ["tagger_type", "tagger_id"], name: "index_taggings_on_tagger_type_and_tagger_id"
  end

  create_table "tags", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "taggings_count", default: 0
    t.datetime "discarded_at"
    t.index ["discarded_at"], name: "index_tags_on_discarded_at"
    t.index ["name"], name: "index_tags_on_name", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address"
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.boolean "admin", default: false, null: false
    t.string "locale"
    t.string "events_view"
    t.string "saved_events_view"
    t.string "calendar_feed_token"
    t.boolean "event_reminders", default: false, null: false
    t.integer "reminder_time", default: 720, null: false
    t.integer "reminder_lead_days", default: 0, null: false
    t.date "last_reminded_on"
    t.index ["calendar_feed_token"], name: "index_users_on_calendar_feed_token", unique: true
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "event_saves", "events"
  add_foreign_key "event_saves", "users"
  add_foreign_key "events", "scrape_runs", column: "created_in_scrape_run_id", on_delete: :nullify
  add_foreign_key "genres", "genres", column: "canonical_id"
  add_foreign_key "genres_styles", "genres", on_delete: :cascade
  add_foreign_key "genres_styles", "styles", on_delete: :cascade
  add_foreign_key "invitations", "users", column: "created_by_id"
  add_foreign_key "invitations", "users", column: "redeemed_by_id"
  add_foreign_key "notification_rules", "users"
  add_foreign_key "notifications", "notification_rules"
  add_foreign_key "notifications", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "scrape_results", "scrape_runs", on_delete: :cascade
  add_foreign_key "sessions", "users"
  add_foreign_key "taggings", "tags"
end
