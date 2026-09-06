class GalleriesController < ApplicationController
  def index
    @sections = portfolio_catalog.sections
  end

  def show
    @gallery = portfolio_catalog.gallery!(params[:id])
    section_id = @gallery["section_id"]
    @section = section_id && portfolio_catalog.section!(section_id)
  rescue PortfolioCatalog::UnknownEntry
    head :not_found
  end
end
