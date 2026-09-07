class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :portfolio_catalog, :build_book_catalog

  private

  def portfolio_catalog
    PortfolioCatalog.current
  end

  def build_book_catalog
    BuildBookCatalog.current
  end
end
