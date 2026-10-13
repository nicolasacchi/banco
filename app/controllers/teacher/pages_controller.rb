module Teacher
  # The browser matrix page (D-289, SPEC B10.8): math.pages-selftest, stored by the operator's console (bin/rails banco:pages_selftest),
  # shown inside the real iframe of a real page of the app, with the report it sends through the bridge. Read-only. The operator runs it
  # on Chrome, Firefox, Safari on iPad and iPhone and Chrome on Android, and writes the results in the RUNBOOK; the pages ship only
  # when every "must be blocked" row holds in every browser.
  class PagesController < Teacher::BaseController
    include FramesPagesOrigin

    def selftest
      @page = Page.find_by(key: "math.pages-selftest")
      @revision = @page&.latest_revision
      @unit = "math:topic"
      return unless @revision

      @view = Pages::Served.view({ "page" => @page.key, "revision" => @revision.id }, student: "preview")
      @view["src"] ||= Pages.enabled? ? Pages.shell_url(@revision.bundle_sha256, Pages::Kit::DEFAULT) : nil
      @view["frame_origin"] = Pages.origin if @view["src"]
    end
  end
end
