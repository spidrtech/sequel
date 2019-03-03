require_relative "spec_helper"

describe "Sequel::Plugins::ThroughAssociations" do

  before do
    class ::User < Sequel::Model
      plugin :through_associations
      one_to_many :user_has_security_groups
      one_to_many :security_groups, through: :user_has_security_groups
      one_to_many :privileges, through: :security_groups
    end
    class ::SecurityGroup < Sequel::Model
      one_to_many :security_group_has_privileges
      one_to_many :privileges, through: :security_group_has_privileges
    end
    class ::Privilege < Sequel::Model
    end
    class ::UserHasSecurityGroup < Sequel::Model
      many_to_one :user
      many_to_one :security_group
      #one_to_many :privileges, through: :security_group
    end
    class ::SecurityGroupHasPrivilege < Sequel::Model
      many_to_one :security_group
      many_to_one :privilege
    end
  end
  after do
    Object.send(:remove_const, :User)
    Object.send(:remove_const, :SecurityGroup)
    Object.send(:remove_const, :UserHasSecurityGroup)
    Object.send(:remove_const, :Privilege)
    Object.send(:remove_const, :SecurityGroupHasPrivilege)
  end

  it "should just work" do
    #assert_equal true, User.new.privileges
  end

end
