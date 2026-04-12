require "digest/sha2"
require "set"
require "active_record/connection_adapters/postgresql_adapter"
require "active_record/connection_adapters/postgresql/branched/branch_manager"
require "active_record/connection_adapters/postgresql/branched/shadow"
require "active_record/connection_adapters/postgresql/branched/schema_dumper"
require "active_record/connection_adapters/postgresql/branched/adapter"
require "active_record/connection_adapters/postgresql/branched/railtie" if defined?(Rails::Railtie)
