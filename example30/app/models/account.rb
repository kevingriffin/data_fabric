class Account < ActiveRecord::Base
  data_fabric :replicated => true, :dynamic_toggle => true
	has_many :figments
end
