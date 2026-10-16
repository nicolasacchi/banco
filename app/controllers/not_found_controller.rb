# Unknown paths and paths that belong to another listener: a 404 that says the same to everyone (a designed page, D-306).
class NotFoundController < ActionController::Base
  # A POST to a route of another listener is a 404 whatever its token says.
  skip_forgery_protection

  def show
    render "shared/error", formats: [ :html ], layout: false, status: :not_found, locals: { status: :not_found }
  end
end
