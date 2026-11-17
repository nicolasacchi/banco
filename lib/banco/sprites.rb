# frozen_string_literal: true

require "digest"
require "yaml"

module Banco
  # The address of an icon sprite (D-347). public/ is served with a one-year cache, so a sprite at a fixed URL never
  # reaches a browser that already has it: every href carries `?v=` and the first 12 hex digits of the SHA-256 of the
  # file's bytes, and a changed sprite is a new URL. bin/build-icons writes the same digests for the browser's code
  # (app/javascript/lesson/sprites.js). Digests are read from the files once per process.
  module Sprites
    ROOT = File.expand_path("../..", __dir__)
    LUCIDE = YAML.safe_load_file(File.join(ROOT, "config/banco/icons.yml")).fetch("lucide").freeze
    DIR = "/vendor/lucide@#{LUCIDE}/".freeze
    DIGEST_SIZE = 12

    class << self
      # "/vendor/lucide@1.54.0/banco-sprite.svg?v=0123456789ab"
      def href(file) = "#{DIR}#{file}?v=#{digest(file)}"

      # The address of an icon: "/vendor/lucide@1.54.0/banco-sprite.svg?v=0123456789ab#gear".
      def icon_href(name, file = "banco-sprite.svg") = "#{href(file)}##{name}"

      def digest(file)
        (@digests ||= {})[file] ||= Digest::SHA256.file(File.join(ROOT, "public", DIR, file)).hexdigest[0, DIGEST_SIZE]
      end

      def reset! = @digests = nil
    end
  end
end
