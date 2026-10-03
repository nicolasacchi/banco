# Unknown paths and paths that belong to another listener: a bare 404.
class NotFoundController < ActionController::Base
  # A POST to a route of another listener is a 404 whatever its token says.
  skip_forgery_protection

  def show
    render plain: "Not found", status: :not_found
  end
end
