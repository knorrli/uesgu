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

ActiveRecord::Schema[8.0].define(version: 2026_06_10_160000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "fuzzystrmatch"
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["hidden"], name: "index_events_on_hidden"
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

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "period_start", null: false
    t.datetime "period_end", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "period_end"], name: "index_notifications_on_user_id_and_period_end"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
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
    t.string "notification_frequency", default: "never", null: false
    t.datetime "last_notified_at"
    t.string "locale"
    t.string "events_view"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "genres", "genres", column: "canonical_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "taggings", "tags"
end
