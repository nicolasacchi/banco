# The plain diff of a page revision against the previous one (SPEC B8): computed by the server with no model, a unified
# diff of every text file and the sizes of binary ones, so a change slipped into a revision that was "only a fix" is visible
# line by line. The reviewer's eleventh point reads it.
require "open3"
require "tmpdir"

module Pages
  module Diff
    TEXT = /\.(mjs|css|svg|json)\z/

    module_function

    # Returns { base_revision_id:, files: [{path:, status:, diff: / bytes_before:, bytes_after:}] }.
    def between(revision, base = revision.base_revision)
      after = bundle(revision)
      before = base ? bundle(base) : {}
      files = (before.keys | after.keys).sort.map do |path|
        a = before[path]
        b = after[path]
        status = a.nil? ? "added" : (b.nil? ? "removed" : (a == b ? "same" : "changed"))
        entry = { path: path, status: status }
        if path.match?(TEXT)
          entry[:diff] = unified(path, a, b) unless status == "same"
        else
          entry[:bytes_before] = a&.bytesize
          entry[:bytes_after] = b&.bytesize
        end
        entry
      end
      { base_revision_id: base&.id, revision_id: revision.id, files: files }
    end

    def bundle(revision)
      files = revision.files.to_h { |f| [ f.path, Pages::Store.read(f.sha256).to_s ] }
      files["page.json"] = JSON.pretty_generate(revision.manifest)
      files
    end

    def unified(path, before, after)
      Dir.mktmpdir("page-diff") do |dir|
        a = File.join(dir, "a")
        b = File.join(dir, "b")
        File.binwrite(a, before.to_s)
        File.binwrite(b, after.to_s)
        out, = Open3.capture2("diff", "-u", "--label", "a/#{path}", "--label", "b/#{path}", a, b)
        out.force_encoding("UTF-8").scrub
      end
    end
  end
end
