require "base64"

module Api
  module V1
    # Free pages (D-290, SPEC B9): list a subject's pages, open one as a folder, submit a revision, read its state and its
    # screenshots, the plain diff against the previous revision. Static validation is synchronous (no Chrome); the
    # validation in the server's Chrome runs in a job. The author works from the embedding card only (B8).
    class PagesController < Api::BaseController
      include SubjectScoped

      before_action :load_subject, only: :index
      before_action :load_revision, only: %i[status shots shot diff]

      MAX_BODY = 3 * 1024 * 1024
      SKELETON_MAIN = <<~JS
        import { banco } from "banco"

        const state = await banco.init()
        const root = document.getElementById("app")
        // Draw with createElement and textContent; time from banco.now(), randomness from banco.random().
        banco.ready()
      JS

      # GET /api/v1/subjects/:subject/pages
      def index
        rows = Page.where(subject: @subject).includes(revisions: %i[validations reviews]).order(:key).filter_map do |page|
          latest = page.latest_revision or next
          verdict = latest.verdict
          { page: page.key, latest_revision_id: latest.id, seq: latest.seq, validation: verdict&.status || "pending", kit_version: verdict&.kit_version,
            reviews: latest.reviews.size, review_blockers: review_count(latest, "blocker"), review_majors: review_count(latest, "major"),
            pinned_by_lessons: Pages::Pins.lesson_keys(latest) }
        end
        render json: { subject: @subject.key, rows: rows }
      end

      # GET /api/v1/pages/:key
      def open
        key = params[:key].to_s
        return refuse("E-FILES", "page", "a page key is SUBJECT.slug, for example math.balance-3d", "banco pages list --subject KEY", 422) unless key.match?(Page::KEY)

        subject = Subject.find_by(key: key.split(".", 2).first)
        return refuse("E-NOT-FOUND", "subject", "no subject #{key.split('.', 2).first.inspect}", "banco status", 404) unless subject

        page = Page.find_by(key: key)
        latest = page&.latest_revision
        card = Pages::Card.for(key, subject)
        files = latest ? files_of(latest) : { "page.json" => JSON.pretty_generate(skeleton(key, subject.key)), "main.mjs" => SKELETON_MAIN }
        render json: { page: key, subject: subject.key, exists: !latest.nil?, latest: latest && latest_row(latest), files: files,
                       card: card, brief: brief_row("page"), libs: Pages::Libs.config.select { |_, l| l["scope"] == "page" }.keys,
                       next: "work from the card only (banco brief show page), then banco page submit DIR --dry-run" }
      end

      # GET /api/v1/page-revisions/:revision
      def status
        latest = @revision.page.latest_revision
        render json: { revision_id: @revision.id, page: @revision.page.key, seq: @revision.seq, superseded: latest.id != @revision.id, rules_version: @revision.rules_version,
                       warnings: @revision.warnings, validation: Pages::Validations.summary(@revision), reviews: @revision.reviews.map { |r| { id: r.id, findings: r.findings.map { |f| f["severity"] }.tally } },
                       pinned_by_lessons: Pages::Pins.lesson_keys(@revision) }
      end

      # GET /api/v1/page-revisions/:revision/shots
      def shots
        row = @revision.verdict
        return refuse("E-NOT-FOUND", "shots", "revision #{@revision.id} has no validation yet", "banco page status #{@revision.id}", 404) unless row

        list = row.shots.map do |s|
          s.slice("kind", "seed_index", "width", "height", "viewport", "sha256", "bytes").merge("available" => PageShots.exist?(s["sha256"]), "path" => "/api/v1/page-revisions/#{@revision.id}/shots/#{s['sha256']}")
        end
        render json: { revision_id: @revision.id, page: @revision.page.key, validation_id: row.id, status: row.status, kit_version: row.kit_version, errors: row.errors_list, shots: list }
      end

      # GET /api/v1/page-revisions/:revision/shots/:sha
      def shot
        known = @revision.validations.any? { |v| v.shots.any? { |s| s["sha256"] == params[:sha] } }
        return refuse("E-NOT-FOUND", "sha", "revision #{@revision.id} has no such image", "banco page shots #{@revision.id} --dir DIR", 404) unless known

        bytes = PageShots.read(params[:sha])
        return refuse("E-NOT-FOUND", "sha", "the image was removed by the purge", "banco page status #{@revision.id}", 404) unless bytes

        send_data bytes, type: "image/webp", disposition: "inline"
      end

      # GET /api/v1/page-revisions/:revision/diff
      def diff
        render json: Pages::Diff.between(@revision)
      end

      # POST /api/v1/pages/submit {page, base, files}
      def submit
        return refuse("E-TOO-LARGE", "body", "the request is over #{MAX_BODY / 1024 / 1024} MB", "shorten the page (the files are at most 1 MB)", 413) if request.raw_post.bytesize > MAX_BODY

        body = parse_json_body or return
        key = body["page"].to_s
        unless key.match?(Page::KEY) && key.size <= 80
          return refuse("E-FILES", "page", "page is a key such as math.balance-3d", "banco page submit DIR", 422)
        end
        subject = Subject.find_by(key: key.split(".", 2).first)
        return refuse("E-NOT-FOUND", "page", "no subject #{key.split('.', 2).first.inspect}", "banco status", 404) unless subject

        files = decode_files(body["files"]) or return
        outcome = Validation::PageChecks.call(files, key: key, subject: subject.key)
        return if refuse_findings(outcome.findings, "fix the page and run banco page submit DIR --dry-run again", dry_run: dry_run?)

        author = require_session("author") or return
        page = Page.find_by(key: key)
        latest = page&.latest_revision
        return unless base_ok?(body["base"], page, latest, key)

        warnings = outcome.findings.warnings.map(&:to_h)
        notes = outcome.hygiene_checked ? [] : [ "the private hygiene list is not on this server: that check was skipped" ]
        if dry_run?
          return render json: { dry_run: true, status: "passed", codes: [], warnings: warnings, bundle_sha256: outcome.bundle_sha256, transfer_kb: (Pages::Libs.transfer_bytes(outcome.manifest["libs"]) + outcome.infos.sum(&:bytes)) / 1024,
                                notes: notes }
        end

        store(key, subject, outcome, warnings, author, latest, notes)
      end

      private

      def review_count(revision, severity) = revision.reviews.sum { |r| r.findings.count { |f| f["severity"] == severity } }

      def load_revision
        @revision = PageRevision.find_by(id: params[:revision])
        refuse("E-NOT-FOUND", "revision", "no page revision #{params[:revision].to_s.first(20).inspect}", "banco pages list --subject KEY", 404) unless @revision
      end

      def latest_row(revision)
        { revision_id: revision.id, seq: revision.seq, validation: revision.verdict&.status || "pending", reviews: revision.reviews.size }
      end

      def skeleton(key, subject)
        { "schema" => "banco.page/1", "key" => key, "subject" => subject, "title_it" => "", "why_free_it" => "", "instructions_it" => "", "alt_it" => "", "fallback_it" => "",
          "libs" => [], "bridge" => 1, "aspect" => "16:9", "min_height" => 320, "uses_seed" => false, "reduced_motion" => "static", "webgl" => false, "roles" => [] }
      end

      # The text files as strings, the binary assets as {"base64": ...}.
      def files_of(revision)
        out = { "page.json" => JSON.pretty_generate(revision.manifest) }
        revision.files.sort_by(&:path).each do |f|
          bytes = Pages::Store.read(f.sha256).to_s
          out[f.path] = f.path.match?(/\.(mjs|css|svg)\z/) ? bytes.dup.force_encoding("UTF-8").scrub : { "base64" => Base64.strict_encode64(bytes) }
        end
        out
      end

      def decode_files(files)
        unless files.is_a?(Hash) && files.any?
          refuse("E-FILES", "files", "send {\"files\": {\"page.json\": \"...\", \"main.mjs\": \"...\"}}", "banco page submit DIR", 422)
          return nil
        end
        files.to_h do |path, value|
          text = if value.is_a?(String) then value.b
          elsif value.is_a?(Hash) && value["base64"].is_a?(String) then Base64.strict_decode64(value["base64"])
          else
            refuse("E-FILES", "files/#{path.to_s.first(60)}", "a file is a string, or {\"base64\": ...} for an image", "banco page submit DIR", 422)
            return nil
          end
          [ path.to_s, text ]
        end
      rescue ArgumentError
        refuse("E-FILES", "files", "a base64 file is not valid base64", "banco page submit DIR", 422)
        nil
      end

      def base_ok?(base, page, latest, key)
        if latest
          return true if base.to_s == latest.id.to_s

          refuse("E-STALE-BASE", "base", "the base is revision #{base.inspect}; the latest of #{key} is #{latest.id}", "banco page open #{key}", 409)
          return false
        end
        return true if base.nil?

        refuse("E-NOT-FOUND", "base", "the page #{key} has no revision #{base}", "banco page submit DIR (a new page has no base)", 404)
        false
      end

      def store(key, subject, outcome, warnings, author, _latest, notes)
        stored = Pages::Submit.store(key: key, subject: subject, outcome: outcome, warnings: warnings, author: author)
        return refuse("E-STALE-BASE", "base", "a revision with these exact files already exists (or another revision of #{key} was stored at the same time)", "banco page open #{key}", 409) if stored.nil?

        revision, replayed = stored
        return render json: { page: key, revision_id: revision.id, seq: revision.seq, replayed: true, warnings: revision.warnings } if replayed

        ValidatePageRevisionJob.perform_later(revision.id)
        render json: { page: key, revision_id: revision.id, seq: revision.seq, replayed: false, warnings: warnings, notes: notes,
                       next: "the validation runs in Chrome now (banco page status #{revision.id}, banco page shots #{revision.id} --dir D); stop here until another session reviews it: banco page-review open #{revision.id}" }, status: :created
      end
    end
  end
end
