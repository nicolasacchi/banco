# What the student's page is told about a pinned free page (SPEC B4, D-289): the page revision's served fields, the poster
# (the validation screenshot, served by the app as WebP), the size of what a click will load and the shell's address on the pages
# origin. The code of the page is never here. `src` is nil while the pages are switched off (BANCO_PAGES_ENABLED=0) or the
# revision has no passed validation: the card then shows its poster, caption and fallback without the button.
module Pages
  module Served
    module_function

    def view(block, student:)
      revision = PageRevision.find_by(id: block["revision"])
      return unavailable unless revision && revision.page.key == block["page"]

      m = revision.manifest
      validation = revision.passed_validation
      poster = PageShots.poster_sha(revision)
      out = { "title_it" => m["title_it"], "instructions_it" => m["instructions_it"], "alt_it" => m["alt_it"], "fallback_it" => m["fallback_it"], "aspect" => m["aspect"],
              "min_height" => m["min_height"], "uses_seed" => m["uses_seed"], "reduced_motion" => m["reduced_motion"],
              "poster" => poster && PageShots.exist?(poster) ? "/page-posters/#{poster}" : nil,
              "transfer_kb" => ((Pages::Libs.transfer_bytes(m["libs"]) + revision.files.sum(&:bytes) + 40_000) / 1024.0).ceil }
      enabled = Pages.enabled? && validation
      out["src"] = enabled ? Pages.shell_url(revision.bundle_sha256, validation.kit_version) : nil
      out["frame_origin"] = enabled ? Pages.origin : nil
      out["seed"] = student.to_s == "preview" ? Pages.teacher_seed : Pages.seed_for(student, revision.page.key)
      out
    end

    def unavailable = { "src" => nil, "frame_origin" => nil, "poster" => nil, "missing" => true }
  end
end
