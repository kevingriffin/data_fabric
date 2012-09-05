require 'test_helper'
require 'test/unit'

class TheWholeBurrito < ActiveRecord::Base
  data_fabric :prefix => 'fiveruns', :replicated => true, :shard_by => :city
end

# Force the base connection to get made
class MixedEnvTaco < ActiveRecord::Base
end


class DatabaseTest < Test::Unit::TestCase

  def setup
    ActiveRecord::Base.configurations = load_database_yml
    DataFabric::ConnectionProxy.shard_pools.clear
  end

  def test_features
    DataFabric.activate_shard :city => :dallas do
      assert_equal 'fiveruns_city_dallas_test_slave', TheWholeBurrito.connection.connection_name
      assert_equal DataFabric::PoolProxy, TheWholeBurrito.connection_pool.class
      assert !TheWholeBurrito.connected?

      # Should use the slave
      burrito = TheWholeBurrito.find(1)
      assert_match 'vr_dallas_slave', burrito.name

      assert TheWholeBurrito.connected?
    end
  end

  def test_mixed_env_connection_master_uses_base_ar_connection
    MixedEnvTaco.establish_connection

    original_connection = MixedEnvTaco.connection

    MixedEnvTaco.class_eval do
      data_fabric :replicated => true
    end

    assert_equal('test_slave', MixedEnvTaco.connection.connection_name)
    assert_not_equal(original_connection, MixedEnvTaco.connection)


    assert_kind_of(DataFabric::ConnectionProxy, MixedEnvTaco.instance_variable_get("@proxy"))
    assert_equal(original_connection,
                 MixedEnvTaco.connection.send("master"),
                 "Master Datbase of MixedEnvTaco should use the default ActiveRecord Database connection")
  end


  def test_live_burrito
    DataFabric.activate_shard :city => :dallas do
      assert_equal 'fiveruns_city_dallas_test_slave', TheWholeBurrito.connection.connection_name

      # Should use the slave
      burrito = TheWholeBurrito.find(1)
      assert_match 'vr_dallas_slave', burrito.name

      # Should use the master
      burrito.reload
      assert_match 'vr_dallas_master', burrito.name

      # ...but immediately set it back to default to the slave
      assert_equal 'fiveruns_city_dallas_test_slave', TheWholeBurrito.connection.connection_name

      # Should use the master
      TheWholeBurrito.transaction do
        burrito = TheWholeBurrito.find(1)
        assert_match 'vr_dallas_master', burrito.name
        burrito.name = 'foo'
        burrito.save!
      end
    end
  end
end
