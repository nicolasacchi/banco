source "https://rubygems.org"

# .ruby-version is the single source of the Ruby version (see test/lib/toolchain_test.rb).
ruby file: ".ruby-version"

gem "rails", "~> 8.1.4"
gem "sqlite3", "~> 2.9"
gem "puma", "~> 8.0"
gem "propshaft"
gem "importmap-rails", "~> 2.2"
gem "turbo-rails"
gem "stimulus-rails"
gem "solid_queue", "~> 1.7"
gem "rails-i18n"

# Headless Chrome client for validation, dry-run and previews (E-01).
gem "ferrum", "0.18.0"
# Needed in production: item and graph submissions are validated against the
# frozen schemas (E-SCHEMA).
gem "json_schemer", "~> 2.4"

gem "tzinfo-data", platforms: %i[ windows jruby ]
gem "bootsnap", require: false

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "cuprite", "~> 0.18"
  gem "minitest-mock"
end
