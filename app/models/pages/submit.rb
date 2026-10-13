# Stores a page revision (D-289): the bytes by content in storage/pages, then one transaction of rows. Used by the API and by the
# operator's console task for the browser matrix page. Returns [revision, replayed] or nil when the same files already exist.
module Pages
  module Submit
    module_function

    # The browser matrix page is served on the production mount without a passed validation (it tries the forbidden on purpose), so
    # only the operator's console may store a revision under its key: never the API, never an agent.
    def reserved?(key) = key.to_s.end_with?(".pages-selftest")

    def store(key:, subject:, outcome:, warnings:, author:, operator: false)
      raise ArgumentError, "the key #{key} is reserved for the operator's console" if reserved?(key) && !operator

      sha = outcome.bundle_sha256 || Bundle.sha256(outcome.manifest, outcome.infos)
      outcome.infos.each { |f| Store.put(f.content) }
      replay = nil
      revision = PageRevision.transaction do
        page = Page.find_or_create_by!(key: key) { |p| p.subject = subject }
        current = page.latest_revision
        if current && current.bundle_sha256 == sha
          replay = current
          next nil
        end
        rev = PageRevision.create!(page: page, seq: (current&.seq || 0) + 1, base_revision_id: current&.id, manifest_json: JSON.generate(outcome.manifest), bundle_sha256: sha,
                                   rules_version: Validation::Rules.version.to_s, warnings_json: JSON.generate(warnings), author_session: author, brief_sha256: Brief.find("page")&.sha256)
        outcome.infos.each { |f| PageFile.create!(page_revision: rev, path: f.path, sha256: f.sha256, bytes: f.bytes, media_type: f.media_type) }
        rev
      end
      replay ? [ replay, true ] : [ revision, false ]
    rescue ActiveRecord::RecordNotUnique
      nil
    end
  end
end
