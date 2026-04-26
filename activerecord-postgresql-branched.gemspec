Gem::Specification.new do |spec|
  spec.name          = "activerecord-postgresql-branched"
  spec.version       = "0.5.0"
  spec.authors       = ["Carl Dawson"]
  spec.summary       = "Branch-aware PostgreSQL adapter for ActiveRecord"
  spec.description   = "A Rails database adapter that gives each git branch its own Postgres schema. Migrations run in isolation. Nobody steps on anyone else's work."
  spec.homepage      = "https://github.com/carldaws/activerecord-postgresql-branched"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "source_code_uri" => "https://github.com/carldaws/activerecord-postgresql-branched",
    "changelog_uri"   => "https://github.com/carldaws/activerecord-postgresql-branched/blob/main/CHANGELOG.md"
  }

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.2"
  spec.add_dependency "railties", ">= 7.2"
  spec.add_dependency "pg"
end
