# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# The free pages origin is mounted before Rails (D-289): the listener decides, so no Rails middleware touches a page.
pages = Banco::PagesApp.new(mode: :production, origin: Pages.origin, parent: Pages.app_origin)
validation = Banco::PagesApp.new(mode: :validate, origin: Pages.validation_origin, parent: Pages.validation_parent)
run Banco::ListenerSwitch.new(Rails.application, production: pages, validation: validation, allow_test_seam: Rails.env.test?)
Rails.application.load_server
