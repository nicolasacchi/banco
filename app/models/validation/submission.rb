module Validation
  # One `banco work submit`: the files an agent sends for an item, checked for what is
  # refused outright (nothing stored: A-06) and then either stored as a new
  # revision or validated in a dry run that writes nothing.
  #
  # Refused: unreadable or missing files (422 E-FILES), too large (413 E-TOO-LARGE),
  # an unknown subject (404 E-NOT-FOUND), a base that is not the latest revision
  # (409 E-STALE-BASE). Everything else is a revision, even a bad one: failed is
  # stored and never approved.
  #
  # Files absent from a submission are carried forward from the base revision, so a
  # verifier can add verify.mjs alone and an author resubmitting item.json keeps the
  # verify.mjs a verifier wrote.
  #
  # Sessions (A-04): the submitting session is author or verifier. Only a verifier
  # session may add or change verify.mjs (422 E-VERIFY-AUTHOR); a verifier changes
  # nothing else, and a session that already holds another role on the item (verifier,
  # reviewer, solver for an author; author, reviewer, solver for a verifier) is refused
  # with 422 E-SESSION-NOT-INDEPENDENT. file_sessions records who wrote each file as it
  # stands, carried forward for the files that did not change.
  class Submission
    class Refused < StandardError
      attr_reader :code, :field, :next_step, :http

      def initialize(code, field, message, next_step, http)
        super(message)
        @code = code
        @field = field
        @next_step = next_step
        @http = http
      end
    end

    NAMES = %w[item.json generator.mjs verify.mjs].freeze
    ASSET = %r{\Aassets/[A-Za-z0-9._-]+\z}

    attr_reader :item, :subject, :base, :files, :key, :session

    def initialize(key:, base:, files:, session:)
      @session = session
      @key = key.to_s
      @base_id = base
      @submitted = files
    end

    # Checks the request and builds the merged file set. Raises Refused.
    def prepare!
      refuse("E-FILES", "item", "an item key is lowercase letters, digits, - and _ (at most 64)", "banco work submit DIR --item KEY", 422) unless key.match?(Item::KEY)
      refuse("E-FILES", "files", "send the files of the revision as an object {name: text}", "banco work submit DIR", 422) unless @submitted.is_a?(Hash) && @submitted.any?
      check_names
      check_sizes
      @item = Item.find_by(key: key)
      @base = base_revision
      @files = merge(@base&.files || {}, @submitted)
      check_item_json
      @subject = @item ? @item.subject : subject_from_item_json
      if @item && @item.subject.key != parsed_item["subject"]
        refuse("E-FILES", "item.json", "the item #{key} belongs to #{@item.subject.key}; item.json says #{parsed_item['subject']}", "banco work open #{key}", 422)
      end
      check_generator_files
      check_sessions
      self
    end

    # The files this submission adds or changes against its base.
    def changed
      @changed ||= @submitted.reject { |name, text| @base&.files&.dig(name) == text }.keys
    end

    # verify.mjs comes from the base unchanged while another file changed: a rejection by it
    # is the verifier's to refresh (E-VERIFY-STALE, D-141).
    def verify_inherited?
      !@base&.files.nil? && @base.files.key?("verify.mjs") && @files["verify.mjs"] == @base.files["verify.mjs"] &&
        @files.except("verify.mjs") != @base.files.except("verify.mjs")
    end

    # Appends the item (first submission) and a revision. Returns [revision, replayed].
    def store!(brief_sha256: nil)
      replayed = nil
      revision = ItemRevision.transaction do
        # The latest revision is read inside the transaction (it takes SQLite's write
        # lock first): a concurrent identical submit is a replay, a different one is a
        # stale base, never a unique-index error (D-073).
        @item ||= Item.find_by(key: key)
        latest = @item && ItemRevision.where(item_id: @item.id).order(:seq).last
        if latest && latest.files == @files
          replayed = latest
        elsif latest&.id != @base&.id
          refuse("E-STALE-BASE", "base", "the base is revision #{@base&.id.inspect}; the latest of #{key} is #{latest&.id.inspect}", "banco work open #{key}", 409)
        else
          @item ||= Item.create!(subject: @subject, key: key, kind: parsed_item["kind"].to_s)
          rest = @files.except("item.json")
          ItemRevision.create!(item: @item, seq: (latest&.seq || 0) + 1, base_revision_id: latest&.id, body_json: @files.fetch("item.json"),
                               files_json: rest.empty? ? nil : JSON.generate(rest), file_sessions_json: JSON.generate(file_sessions(latest)),
                               author_session_id: author_session_id(latest), brief_sha256: brief_sha256)
        end
      end
      replayed ? [ replayed, true ] : [ revision, false ]
    end

    def parsed_item = @parsed_item ||= JSON.parse(@files.fetch("item.json"))

    private

    # {file => session id}: the base's map, with this session on every file it wrote.
    def file_sessions(latest)
      map = (latest&.file_sessions || {}).slice(*@files.keys)
      (changed & @files.keys).each { |name| map[name] = session.id }
      @files.each_key { |name| map[name] ||= session.id }
      map
    end

    def author_session_id(latest)
      session.role == "author" && changed.include?("item.json") ? session.id : latest&.author_session_id || (session.role == "author" ? session.id : nil)
    end

    def check_sessions
      if changed.include?("verify.mjs") && session.role != "verifier"
        refuse("E-VERIFY-AUTHOR", "verify.mjs", "verify.mjs is written by a verifier session: session #{session.id} is a #{session.role} session", "banco session new --role verifier --agent NAME --model MODEL; banco work open #{key} --role verifier", 422)
      end
      if session.role == "verifier"
        other = changed - [ "verify.mjs" ]
        refuse("E-SESSION-NOT-INDEPENDENT", other.first, "a verifier session sends verify.mjs only, not #{other.join(', ')}", "banco work open #{key} --role verifier", 422) if other.any?
      end
      return unless @item && changed.any?

      held = ItemSessions.new(@item).conflicts(session.id, session.role)
      return if held.empty?

      refuse("E-SESSION-NOT-INDEPENDENT", "X-Banco-Session", "session #{session.id} already acted as #{held.join(' and ')} on #{key}: the #{session.role} must be another session",
             "banco session new --role #{session.role} --agent NAME --model MODEL", 422)
    end

    def refuse(code, field, message, next_step, http)
      raise Refused.new(code, field, message, next_step, http)
    end

    def check_names
      bad = @submitted.keys.find { |n| !NAMES.include?(n) && !n.to_s.match?(ASSET) }
      refuse("E-FILES", bad.to_s, "#{bad.inspect} is not a file of an item revision (item.json, generator.mjs, verify.mjs, assets/NAME)", "banco work open ITEM", 422) if bad
      text = @submitted.find { |_n, v| !v.is_a?(String) || !v.valid_encoding? }
      refuse("E-FILES", text[0].to_s, "#{text[0]} is not UTF-8 text", "banco work submit DIR", 422) if text
    end

    def check_sizes
      limit = Rules.get(:files, :max_file_bytes)
      big = @submitted.find { |n, v| (NAMES.include?(n)) && v.bytesize > limit }
      refuse("E-TOO-LARGE", big[0], "#{big[0]} is over #{limit / 1024} KB", "split the generator or shorten the item", 413) if big
      total = @submitted.values.sum(&:bytesize)
      refuse("E-TOO-LARGE", "files", "the submission is over #{Rules.get(:files, :max_total_bytes) / (1024 * 1024)} MB", "send fewer or smaller files", 413) if total > Rules.get(:files, :max_total_bytes)
    end

    def base_revision
      latest = @item&.latest_revision
      if latest
        unless @base_id.to_i == latest.id
          refuse("E-STALE-BASE", "base", "the base is revision #{@base_id.inspect}; the latest of #{key} is #{latest.id}", "banco work open #{key}", 409)
        end
        latest
      elsif !@base_id.nil?
        refuse("E-NOT-FOUND", "base", "the item #{key} has no revision #{@base_id}", "banco work submit DIR (a new item has no base)", 404)
      end
    end

    def merge(base_files, submitted) = base_files.merge(submitted)

    def check_item_json
      text = @files["item.json"]
      refuse("E-FILES", "item.json", "item.json is missing", "put item.json in the folder", 422) unless text
      doc = JSON.parse(text)
      refuse("E-FILES", "item.json", "item.json is not a JSON object", "fix item.json", 422) unless doc.is_a?(Hash)
    rescue JSON::ParserError => e
      refuse("E-FILES", "item.json", "item.json is not valid JSON: #{e.message.first(100)}", "fix item.json", 422)
    end

    def subject_from_item_json
      Subject.find_by(key: parsed_item["subject"].to_s) ||
        refuse("E-NOT-FOUND", "item.json", "unknown subject #{parsed_item['subject'].inspect}", "check the subject key", 404)
    end

    # A generator that item.json names must be there; a stray generator.mjs is left to
    # the code scan.
    def check_generator_files
      refuse("E-FILES", "generator.mjs", "item.json names generator.mjs but the revision has none", "add generator.mjs", 422) if parsed_item["generator"] && !@files.key?("generator.mjs")
    end
  end
end
