file = defined?(Rails) ? Rails.root.join("config", "database.yml") : File.join(RAILS_ROOT, "config", "database.yml")
DataFabric::DynamicSwitching.load_configurations(file)
