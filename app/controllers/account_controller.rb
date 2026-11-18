# Account and password (D-357): how signing in works. banco has no passwords; the access portal in front of it does. The portal's
# address is BANCO_AUTH_URL and its numbers are in config/banco/account.yml (Privacy::Portal).
class AccountController < ApplicationController
  include InfoPage

  def show
    @portal_url = Privacy::Portal.url
    @phrases = Privacy::Portal.phrases
  end
end
