require "test_helper"

class AccentSystemTest < ActiveSupport::TestCase
  setup do
    @stylesheet = Rails.root.join("app/assets/stylesheets/application.css").read
  end

  test "every catalog accent has a dark-ground rule and a light-ground partner" do
    accents = PortfolioCatalog.current.sections.pluck("accent").uniq
    assert_equal PortfolioCatalog::ACCENTS.sort, accents.sort

    accents.each do |accent|
      assert_includes @stylesheet, ".accent--#{accent} {", "missing rule for accent #{accent}"
      assert_includes @stylesheet, "--#{accent}-ink:", "missing light-ground partner for #{accent}"
    end
  end

  test "every spectrum stop the helper can emit is defined, and the index wraps" do
    view = ApplicationController.helpers
    stops = ApplicationHelper::SPECTRUM_STOPS

    (0...stops).each do |index|
      assert_includes @stylesheet, ".#{view.spectrum_class(index)} {", "missing stop for index #{index}"
    end
    assert_equal view.spectrum_class(0), view.spectrum_class(stops)
  end
end
