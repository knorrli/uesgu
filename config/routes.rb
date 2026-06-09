Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get 'up' => 'rails/health#show', as: :rails_health_check

  mount MissionControl::Jobs::Engine, at: '/admin/jobs'

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

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

  resources :events, only: [:index, :destroy] do
    collection do
      get :day
    end
  end
  resources :styles, only: :index do
    collection do
      post :chips
    end
  end
  resources :tags, only: [:index, :edit, :update, :destroy] do
    collection do
      post :chips
    end
  end

  scope :admin do
    get '', to: 'admin#index', as: :admin
    post 'reload_styles', to: 'admin#reload_styles', as: :reload_styles
    post 'scrape_events', to: 'admin#scrape_events', as: :scrape_events
    post 'clear_events', to: 'admin#clear_events', as: :clear_events

    resources :genre_style_assignments, only: [:index, :create, :destroy]
  end
end
