class BuildBooksController < ApplicationController
  def show
    @build_book = build_book_catalog.build_book!(params[:id])
    @project = portfolio_catalog.project!(@build_book.fetch("project_id"))
    @section = portfolio_catalog.section!(@project.fetch("section_id"))
    @gallery = portfolio_catalog.gallery!(@project.fetch("gallery_id"))
  rescue BuildBookCatalog::UnknownEntry, PortfolioCatalog::UnknownEntry
    head :not_found
  end
end
