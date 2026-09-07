Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "led-art" => "sections#show", defaults: { id: "led-art" }, as: :led_art
  get "cosplay" => "sections#show", defaults: { id: "cosplay" }, as: :cosplay
  get "forge" => "sections#show", defaults: { id: "forge" }, as: :forge

  get "led-art/instrument-art" => "projects#show", defaults: { id: "instrument-art" }, as: :instrument_art
  get "led-art/cadenza" => "projects#show", defaults: { id: "cadenza" }, as: :cadenza
  get "cosplay/disco-chief" => "projects#show", defaults: { id: "disco-chief" }, as: :disco_chief
  get "cosplay/russell-glow" => "projects#show", defaults: { id: "russell-glow" }, as: :russell_glow
  get "cosplay/russell-glow/build-book" => "build_books#show", defaults: { id: "russell-glow" }, as: :russell_glow_build_book
  get "cosplay/darth-daddy" => "projects#show", defaults: { id: "darth-daddy" }, as: :darth_daddy

  get "galleries" => "galleries#index", as: :galleries
  get "galleries/:id" => "galleries#show", constraints: { id: /[a-z0-9]+(?:-[a-z0-9]+)*/ }, as: :gallery

  get "about" => "pages#about", as: :about
  get "contact" => "pages#contact", as: :contact
  get "sitemap" => "sitemap#show", defaults: { format: :xml }, as: :sitemap

  root "home#index"
end
