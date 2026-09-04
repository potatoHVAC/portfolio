class SectionsController < ApplicationController
  def show
    @section = portfolio_catalog.section!(params[:id])
    @projects = portfolio_catalog.projects_for(@section.fetch("id"))
    @galleries = portfolio_catalog.galleries_for(@section.fetch("id"))
  rescue PortfolioCatalog::UnknownEntry
    head :not_found
  end
end
