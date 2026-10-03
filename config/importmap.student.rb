# The importmap of the student's pages (X-02): Stimulus, our controllers and item
# templates, and the two libraries that the app serves itself from public/vendor at
# pinned versions (each directory has a SHA256SUMS that CI checks). No Turbo, no
# application.js, nothing from a CDN.
pin "diagnosis"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/student_controllers", under: "student_controllers"
pin_all_from "app/javascript/items", under: "items"
pin "mathlive", to: "/vendor/mathlive@0.111.0/mathlive.min.mjs", preload: false
pin "katex", to: "/vendor/katex@0.19.0/katex.mjs", preload: false
