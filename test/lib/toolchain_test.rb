require "test_helper"

# .ruby-version is the single source of the Ruby version (E-02): the running
# Ruby, the Dockerfile ARG and the CI all follow it.
class ToolchainTest < ActiveSupport::TestCase
  ROOT = Rails.root

  def ruby_version
    ROOT.join(".ruby-version").read.strip
  end

  test "running ruby matches .ruby-version" do
    assert_equal ruby_version, RUBY_VERSION
  end

  test "Dockerfile ARG RUBY_VERSION matches .ruby-version" do
    arg = ROOT.join("Dockerfile").read[/^ARG RUBY_VERSION=(\S+)/, 1]
    assert_equal ruby_version, arg
  end

  test "Dockerfile base image is ruby slim with that version" do
    assert_match(/^FROM docker\.io\/library\/ruby:\$RUBY_VERSION-slim /, ROOT.join("Dockerfile").read)
  end

  test "Gemfile takes its ruby from .ruby-version" do
    assert_match(/^ruby file: "\.ruby-version"/, ROOT.join("Gemfile").read)
  end

  test "CI reads the ruby version from .ruby-version" do
    ci = ROOT.join(".github/workflows/ci.yml").read
    assert_no_match(/ruby-version:\s*['"]?\d/, ci)
  end

  test "node in the Dockerfile matches the pinned version" do
    dockerfile = ROOT.join("Dockerfile").read
    assert_match(/^ARG NODE_VERSION=26\.7\.0$/, dockerfile)
    assert_match(/^FROM docker\.io\/library\/node:\$\{NODE_VERSION\}-slim AS node$/, dockerfile)
  end

  # D-330: the image builds the CLI's release build with the Go that go.mod asks for, and ships it at /rails/dist.
  test "the cli stage builds with the Go of go.mod and the final image carries its dist" do
    dockerfile = ROOT.join("Dockerfile").read
    go_mod = ROOT.join("go.mod").read[/^go (\d+\.\d+)/, 1]
    pinned = dockerfile[/^ARG GO_VERSION=(\S+)$/, 1]
    assert pinned&.start_with?("#{go_mod}."), "ARG GO_VERSION=#{pinned.inspect} is not a #{go_mod}.x release"
    assert_match(/^FROM docker\.io\/library\/golang:\$\{GO_VERSION\} AS cli$/, dockerfile)
    assert_match(%r{^RUN GIT_SHA=\$\{GIT_SHA\} DIST_DIR=/dist bin/build-cli-dist$}, dockerfile)
    assert_match(%r{^COPY --chown=\$\{APP_UID\}:\$\{APP_GID\} --from=cli /dist /rails/dist$}, dockerfile)
    ignored = ROOT.join(".dockerignore").read.lines.map(&:strip)
    assert_includes ignored, "/dist"
    %w[bot api decisions].each { |doc| assert_includes ignored, "!/docs/#{doc}.md" }
  end

  test ".dockerignore keeps the private working directories (briefs/ is served at runtime and stays) out of the image" do
    ignored = ROOT.join(".dockerignore").read.lines.map(&:strip)
    %w[/prep /.claude].each { |dir| assert_includes ignored, dir }
  end
end
