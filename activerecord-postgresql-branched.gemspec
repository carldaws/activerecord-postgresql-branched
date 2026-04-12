Gem::Specification.new do |spec|
  spec.name          = "activerecord-postgresql-branched"
  spec.version       = "0.1.0"
  spec.authors       = ["Carl Dawson"]
  spec.summary       = "Branch-aware PostgreSQL adapter for ActiveRecord"
  spec.description   = "A Rails database adapter that gives each git branch its own Postgres schema. Migrations run in isolation. Nobody steps on anyone else's work."
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.1"
  spec.add_dependency "pg"
end
