class SitemapController < ApplicationController
  def show
    @paths = portfolio_catalog.public_paths
  end
end
