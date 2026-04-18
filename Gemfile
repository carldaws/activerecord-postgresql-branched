source "https://rubygems.org"

gemspec

rails_version = ENV["RAILS_VERSION"]
if rails_version == "edge"
  gem "activerecord", github: "rails/rails"
  gem "railties", github: "rails/rails"
elsif rails_version
  gem "activerecord", "~> #{rails_version}.0"
  gem "railties", "~> #{rails_version}.0"
end

gem "rake"
gem "minitest"
