class HomeController < ApplicationController
  def index
    @sections = portfolio_catalog.sections
    @led_projects = portfolio_catalog.featured_projects_for("led-art")
  end
end
