Rails.application.routes.draw do
  # Canonical host. üsgu.ch (punycode xn--sgu-goa.ch) is the public web domain.
  # Render also terminates TLS for uesgu.ch (the code/email domain) and the www
  # variants, so 301 every one of those to the umlaut domain, preserving path +
  # query. www.üsgu.ch is included here too so Rails is the single source of
  # truth for canonicalization rather than relying on Render's www handling.
  redirecting_hosts = ["www.#{AppHost::PUBLIC}", AppHost::CODE, "www.#{AppHost::CODE}"]
  constraints(host: /\A(?:#{redirecting_hosts.map { |h| Regexp.escape(h) }.join('|')})\z/i) do
    match "(*path)", via: :all,
      to: redirect(status: 301) { |_params, request| "https://#{AppHost::PUBLIC}#{request.fullpath}" }
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (manifest is linked in the
  # layout head; the service worker is registered in application.js).
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root 'events#index'

  # Public "add üsgu to your phone" page — no account required (installing is the
  # most important first step for users). Linked from the header.
  get 'install', to: 'install#show', as: :install

  resource :session
  resource :registration, only: %i[new create destroy]
  get 'signup', to: 'registrations#new'
  resource :settings, only: %i[show update]
  resources :notifications, only: %i[index show]

  # "Save this show": the saved-shows list + an inline per-event save toggle.
  resources :saved_events, only: %i[index] do
    post :toggle, on: :collection
    # The day-of reminder for saved shows is a property of the saved-shows feature,
    # so its opt-in lives on this page (not Settings); a small background toggle.
    patch :reminders, on: :collection
  end

  # Subscribable ICS feed of the user's saved shows. The public feed is keyed by
  # an unguessable token (no session); create/destroy mint and revoke it.
  resource :calendar_feed, only: %i[create destroy]
  # format: true keeps the ".ics" extension in the URL (some calendar clients
  # insist on it); the token segment has no dots, so it never swallows it.
  get "calendar/:token", to: "calendar_feeds#show", as: :public_calendar_feed,
      constraints: { format: "ics" }, format: true

  # Saved filters (a saved landing-page filter, with notification delivery
  # optional — see SavedFilter). new/create save the current events filter;
  # edit/update tune it; fire runs it on demand ("Fire now" — test without waiting
  # for the schedule). There's no pause toggle: a filter delivers iff its in-app
  # channel is on, edited on the form like any other channel.
  resources :saved_filters, only: %i[index new create edit update destroy] do
    member do
      post :fire
    end
  end

  # Web Push opt-in/out for the current device. Keyed by endpoint (in the body),
  # not an id, so a singular-style pair of bare routes fits better than a
  # resource collection.
  post 'push_subscriptions' => 'push_subscriptions#create'
  delete 'push_subscriptions' => 'push_subscriptions#destroy'
  # Send a test push to the current device, so a user can verify it arrives.
  post 'push_subscriptions/test' => 'push_subscriptions#test'

  # Living styleguide: a single admin-only page that renders every shared UI
  # element with the real bundled CSS, so it stays in sync as the styles change
  # (rather than rotting like a static design doc). See docs/ui-audit.md.
  get "styleguide" => "styleguide#index", as: :styleguide

  resources :events, only: [:index, :destroy]
  resources :tags, only: [:index, :edit] do
    collection do
      post :chips
    end
  end

  scope :admin do
    get '', to: 'admin#index', as: :admin

    # Genre curation. index/edit browse + open the per-genre editor; queue is the
    # "tinder" flow serving the next genre not yet filed into the tree; set_parent
    # files a genre under a parent (the tree's curation action); ignore/hide/block
    # set a disposition, restore clears it; merge folds the genre into a canonical
    # one (a semantic alias).
    resources :genres, only: %i[index edit] do
      member do
        post :set_parent
        post :ignore
        post :hide
        post :block
        post :restore
        post :merge
      end
      collection do
        get :queue
        # Read-only hierarchy view of the curated genre tree.
        get :tree
        # Selection chips for the per-event genre-override combobox (admin only).
        post :chips
      end
    end
  end

  # Account moderation + the invite-only gate. Namespaced (Admin::) so these
  # get their own admin_users_/admin_invitations_ helpers, distinct from the
  # legacy scoped dashboard/genre routes above.
  namespace :admin do
    resources :users, only: %i[index show destroy]
    resources :invitations, only: %i[index create destroy]
    # Scraper run oversight: nightly sweep health + per-venue outcomes. create
    # triggers a full sweep on demand (runs in a background thread).
    resources :scrape_runs, only: %i[index show create]

    # Catalogue browsers reached from the dashboard stats: events (the scraped
    # table) and locations (derived from the location tags). Each mirrors the
    # genres index idiom — filter / sort / search / paginate. (Genres keep their
    # own legacy scoped route above, with edit/queue actions these two don't
    # need.) Events additionally get
    # show/update for per-event manual correction; revert releases one locked
    # field back to the scraper; destroy dismisses (soft-deletes) it and undismiss
    # restores it.
    resources :events, only: %i[index show update destroy] do
      member do
        patch :revert
        patch :undismiss
        patch :merge      # pin this event as a duplicate of another (canonical_id)
        patch :unmerge    # pin this event as standalone (split a wrong auto-merge)
      end
    end
    resources :locations, only: %i[index]

    # Admin-authored rules that auto-discard junk scraped events by text match.
    # preview is a live, save-less lookup of the events a (possibly unsaved) rule
    # would target, for spotting false positives before committing.
    resources :discard_rules, except: %i[show] do
      collection { get :preview }
    end
  end
end
