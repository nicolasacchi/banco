// Entry point of the student's pages (X-02). Turbo is deliberately not loaded:
// the Diagnosi page is one page that fetches its items itself.
import { Application } from "@hotwired/stimulus"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

const application = Application.start()
application.debug = false
window.Stimulus = application
eagerLoadControllersFrom("student_controllers", application)
