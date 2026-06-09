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
    # assigns styles; dismiss/restore toggle "won't fix".
    resources :genres, only: %i[index edit update] do
      member do
        post :dismiss
        post :exclude
        post :restore
      end
      collection do
        get :queue
      end
    end
  end
end
