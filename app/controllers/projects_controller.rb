class ProjectsController < ApplicationController
  def show
    @project = portfolio_catalog.project!(params[:id])
    @section = portfolio_catalog.section!(@project.fetch("section_id"))
    @gallery = portfolio_catalog.gallery!(@project.fetch("gallery_id"))
  rescue PortfolioCatalog::UnknownEntry
    head :not_found
  end
end
