Rails.application.routes.draw do
  # Canonical host. üsgu.ch (punycode xn--sgu-goa.ch) is the public web domain.
  # Render also terminates TLS for uesgu.ch (the code/email domain) and the www
  # variants, so 301 every one of those to the umlaut domain, preserving path +
  # query. www.üsgu.ch is included here too so Rails is the single source of
  # truth for canonicalization rather than relying on Render's www handling.
  constraints(host: /\A(?:www\.xn--sgu-goa\.ch|(?:www\.)?uesgu\.ch)\z/i) do
    match "(*path)", via: :all,
      to: redirect(status: 301) { |_params, request| "https://xn--sgu-goa.ch#{request.fullpath}" }
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

  resource :session
  resource :registration, only: %i[new create destroy]
  get 'signup', to: 'registrations#new'
  resource :settings, only: %i[show update]
  resource :favorites, only: %i[show update] do
    post :toggle
  end
  resources :notifications, only: %i[index show]

  # Web Push opt-in/out for the current device. Keyed by endpoint (in the body),
  # not an id, so a singular-style pair of bare routes fits better than a
  # resource collection.
  post 'push_subscriptions' => 'push_subscriptions#create'
  delete 'push_subscriptions' => 'push_subscriptions#destroy'
  # Send a test push to the current device, so a user can verify it arrives.
  post 'push_subscriptions/test' => 'push_subscriptions#test'

  resources :events, only: [:index, :destroy]
  resources :styles, only: [] do
    collection do
      post :chips
    end
  end
  resources :tags, only: [:index, :edit] do
    collection do
      post :chips
    end
  end

  scope :admin do
    get '', to: 'admin#index', as: :admin

    # Genre → style mapping. index/edit are standard CRUD over all genres in
    # use; queue is the "tinder" flow serving the next unmapped genre; update
    # assigns styles; ignore/hide/block set a disposition, restore clears it;
    # merge folds the genre into a canonical one (a semantic alias).
    resources :genres, only: %i[index edit update] do
      member do
        post :ignore
        post :hide
        post :block
        post :restore
        post :merge
      end
      collection do
        get :queue
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
    # table), styles (the curated vocabulary), and locations (derived from the
    # location tags). Each mirrors the genres index idiom — filter / sort /
    # search / paginate. (Genres keep their own legacy scoped route above, with
    # edit/queue actions these three don't need.) Events additionally get
    # show/update for per-event manual correction; revert releases one locked
    # field back to the scraper.
    resources :events, only: %i[index show update] do
      member { patch :revert }
    end
    resources :styles, only: %i[index]
    resources :locations, only: %i[index]
  end
end
