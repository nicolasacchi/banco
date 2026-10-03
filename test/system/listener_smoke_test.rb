require "application_system_test_case"

# Real browser against a real server socket: the listener tag comes from the
# accepted socket's local port, with no test seam involved.
class ListenerSmokeTest < ApplicationSystemTestCase
  test "the web listener serves /up and refuses the API paths" do
    visit "/up"
    assert_equal 200, page.status_code

    visit "/api/v1/schema"
    assert_equal 404, page.status_code

    visit "/teacher"
    assert_equal 403, page.status_code
  end
end
