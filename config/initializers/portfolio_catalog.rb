# Fail startup instead of serving a partially valid content graph.
Rails.application.config.to_prepare { PortfolioCatalog.current }
