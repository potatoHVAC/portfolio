class GalleriesController < ApplicationController
  def index
    @sections = portfolio_catalog.sections
  end

  def show
    @gallery = portfolio_catalog.gallery!(params[:id])
    @section = portfolio_catalog.section!(@gallery.fetch("section_id"))
  rescue PortfolioCatalog::UnknownEntry
    head :not_found
  end
end
