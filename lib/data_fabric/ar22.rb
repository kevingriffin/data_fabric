
class ActiveRecord::ConnectionAdapters::ConnectionHandler
  def clear_active_connections_with_data_fabric!
    clear_active_connections_without_data_fabric!
    DataFabric::ConnectionProxy.shard_pools.each_value { |pool| pool.release_connection }
  end
  alias_method_chain :clear_active_connections!, :data_fabric
end

module DataFabric
  module Extensions
    def self.included(model)
      # Wire up ActiveRecord::Base
      model.extend ClassMethods
      ConnectionProxy.shard_pools = {}
    end

    # Class methods injected into ActiveRecord::Base
    module ClassMethods
      def data_fabric(options)
        DataFabric.log { "Creating data_fabric proxy for class #{name}" }
        @proxy = DataFabric::ConnectionProxy.new(self, options)

        class << self
          alias_method :__original_ar_connection, :connection
          def connection
            @proxy
          end

          def connected?
            @proxy.connected?
          end

          def remove_connection(klass=self)
            DataFabric.log(Logger::WARN) { "remove_connection not implemented by data_fabric" }
          end

          def connection_pool
            raise "dynamic connection switching means you cannot get direct access to a pool"
          end
        end
      end
    end
  end

  class ConnectionProxy
    cattr_accessor :shard_pools

    def initialize(model_class, options)
      @model_class = model_class
      @replicated  = options[:replicated]
      @shard_group = options[:shard_by]
      @prefix      = options[:prefix]
      set_role('slave') if @replicated

      @model_class.send :include, ActiveRecordConnectionMethods if @replicated
    end

    delegate :insert, :update, :delete, :create_table, :rename_table, :drop_table, :add_column, :remove_column,
      :change_column, :change_column_default, :rename_column, :add_index, :remove_index, :initialize_schema_information,
      :dump_schema_information, :execute, :execute_ignore_duplicate, :to => :master

    delegate :insert_many, :to => :master # ar-extensions bulk insert support

    def transaction(start_db_transaction = true, &block)
      # Transaction is not re-entrant in SQLite 3 so we
      # need to track if we've already started an XA to avoid
      # calling it twice.
      return yield if in_transaction?

      with_master do
        connection.transaction(start_db_transaction, &block)
      end
    end

    def method_missing(method, *args, &block)
      DataFabric.log(Logger::DEBUG) { "Calling #{method} on #{connection}" }
      r = connection.send(method, *args, &block)
      # Don't hit method missing again
      self.class_eval(<<-EVL, __FILE__, __LINE__)
        def #{method}(*args, &block)
          connection.send("#{method}", *args, &block)
        end
      EVL
      r
    end

    def connection_name
      connection_name_builder.join('_')
    end

    def with_master
      # Allow nesting of with_master.
      old_role = current_role
      set_role('master')
      yield
    ensure
      set_role(old_role)
    end

    def connected?
      current_pool.connected?
    end

  private

    def in_transaction?
      current_role == 'master'
    end

    def current_pool
      name = connection_name

      self.class.shard_pools[name] ||= load_up_connection_pool_for_connection_name(name)
    end

    def load_up_connection_pool_for_connection_name(name)
      if @replicated && /#{Rails.env}_master/ =~ name
        # take the active record default connection instead of making an additional connection to the same db
        @model_class.__original_ar_connection
      else
        config = ActiveRecord::Base.configurations[name]
        raise ArgumentError, "Unknown database config: #{name}, have #{ActiveRecord::Base.configurations.inspect}" unless config
        ActiveRecord::ConnectionAdapters::ConnectionPool.new(spec_for(config))
      end
    end

    def spec_for(config)
      # XXX This looks pretty fragile.  Will break if AR changes how it initializes connections and adapters.
      config = config.symbolize_keys
      adapter_method = "#{config[:adapter]}_connection"
      initialize_adapter(config[:adapter])
      ActiveRecord::Base::ConnectionSpecification.new(config, adapter_method)
    end

    def initialize_adapter(adapter)
      begin
        require 'rubygems'
        gem "activerecord-#{adapter}-adapter"
        require "active_record/connection_adapters/#{adapter}_adapter"
      rescue LoadError
        begin
          require "active_record/connection_adapters/#{adapter}_adapter"
        rescue LoadError
          raise "Please install the #{adapter} adapter: `gem install activerecord-#{adapter}-adapter` (#{$!})"
        end
      end
    end

    def connection_name_builder
      @connection_name_builder ||= begin
        clauses = []
        clauses << @prefix if @prefix
        clauses << @shard_group if @shard_group
        clauses << StringProxy.new { DataFabric.active_shard(@shard_group) } if @shard_group
        clauses << RAILS_ENV
        clauses << StringProxy.new { current_role } if @replicated
        clauses
      end
    end

    def connection
      cp = current_pool
      if cp.kind_of?( ActiveRecord::ConnectionAdapters::MysqlAdapter )
        cp
      else
        begin
          cp.connection
        rescue Mysql::Error, ActiveRecord::StatementInvalid => err
          if current_role == 'slave' && err.message =~ /Can't connect to MySQL server/
            # Try master
            DataFabric.log(Logger::ERROR) { "Slave DB died #{err.class} #{err.message} trying with master" }
            master
          else
            raise err
          end
        end
      end
    end

    def set_role(role)
      Thread.current[:data_fabric_role] = role
    end

    def current_role
      Thread.current[:data_fabric_role] || 'slave'
    end

    def master
      with_master { return connection }
    end
  end

  module ActiveRecordConnectionMethods
    def self.included(base)
      base.alias_method_chain :reload, :master
    end

    def reload_with_master(*args, &block)
      connection.with_master { reload_without_master }
    end
  end

  class StringProxy
    def initialize(&block)
      @proc = block
    end
    def to_s
      @proc.call
    end
  end
end
