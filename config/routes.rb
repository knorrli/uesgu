Rails.application.routes.draw do
  redirecting_hosts = ["www.#{AppHost::PUBLIC}", AppHost::CODE, "www.#{AppHost::CODE}"]
  constraints(host: /\A(?:#{redirecting_hosts.map { |h| Regexp.escape(h) }.join('|')})\z/i) do
    match "(*path)", via: :all,
      to: redirect(status: 301) { |_params, request| "https://#{AppHost::PUBLIC}#{request.fullpath}" }
  end

  get "up" => "rails/health#show", as: :rails_health_check

  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "events#index"

  get "install", to: "install#show", as: :install

  get "about", to: "pages#about", as: :about
  get "privacy", to: "pages#privacy", as: :privacy

  resource :session
  resource :registration, only: %i[new create destroy]
  get "signup", to: "registrations#new"
  resource :settings, only: %i[show update]
  resources :notifications, only: %i[index show] do
    post :mark_all_read, on: :collection
  end

  resources :saved_events, only: %i[index] do
    post :toggle, on: :collection
    patch :reminders, on: :collection
  end

  resource :calendar_feed, only: %i[create destroy]
  get "calendar/:token", to: "calendar_feeds#show", as: :public_calendar_feed,
      constraints: { format: "ics" }, format: true

  resource :capture, only: %i[show create] do
    post :extract
    post :drop
    get :manual
    post :genre_chips
  end

  resources :saved_filters, only: %i[index new create edit update destroy] do
    member do
      post :fire
    end
  end

  post "push_subscriptions" => "push_subscriptions#create"
  delete "push_subscriptions" => "push_subscriptions#destroy"
  post "push_subscriptions/test" => "push_subscriptions#test"

  get "styleguide" => "styleguide#index", as: :styleguide

  resources :events, only: [:index, :destroy]
  resources :tags, only: [:index, :edit] do
    collection do
      post :chips
      get "filter_options/:field", action: :filter_options, as: :filter_options,
          constraints: { field: /what|where/ }
    end
  end

  scope :admin do
    get "", to: "admin#index", as: :admin

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
        get :tree
        post :chips
      end
    end
  end

  namespace :admin do
    resources :users, only: %i[index show destroy] do
      member { patch :toggle_contributor }
    end
    resources :invitations, only: %i[index create destroy]
    resources :scrape_runs, only: %i[index show create] do
      collection do
        post :snooze
        post :wake
      end
    end

    resources :venue_leads, only: %i[index]

    resources :extraction_attempts, only: %i[index]

    resources :events, only: %i[index show update destroy] do
      collection do
        get :search
      end
      member do
        patch :revert
        patch :undismiss
        patch :merge
        patch :unmerge
      end
    end
    resources :locations, only: %i[index]

    resources :localities, only: %i[index edit] do
      member do
        post :merge
        post :unmerge
      end
    end

    resources :places, only: %i[index edit update] do
      member do
        post :merge
        post :unmerge
      end
    end

    get "scraper_coverage", to: "scraper_coverage#index", as: :scraper_coverage

    resources :discard_rules, except: %i[show] do
      collection { get :preview }
    end
  end
end
