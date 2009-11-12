# == Attributes
#   subscriptions:      all subscriptions for the plan
#   rate_cents:         how much this plan costs, in cents
#   rate:               how much this plan costs, in Money
#   yearly:             whether this plan cycles yearly or monthly
#   key:                A string that is used to reference a feature_set that corresponds to this plan in config/freemium_feature_sets.yml


module Freemium
  module SubscriptionPlan
    include Rates
    
    def self.included(base)
      base.class_eval do
        # yes, subscriptions.subscription_plan_id may not be null, but
        # this at least makes the delete not happen if there are any active.
        has_many :subscriptions, :dependent => :nullify, :class_name => "FreemiumSubscription", :foreign_key => :subscription_plan_id
        has_and_belongs_to_many :coupons, :class_name => "FreemiumSubscriptionPlan", 
          :join_table => :freemium_coupons_subscription_plans, :foreign_key => :subscription_plan_id, :association_foreign_key => :coupon_id
        
        composed_of :rate, :class_name => 'Money', :mapping => [ %w(rate_cents cents) ], :allow_nil => true

        ## JCS: This used to validate 'redemption_key', which only exists on the coupon, and it would always fail.
        ## I'm still not sure how that was supposed to wor, but I'm going to validate "key" which makes more sense.
        validates_uniqueness_of :key
        validates_presence_of :name
        validates_presence_of :rate_cents
      end
    end
    
    def features
      Freemium::FeatureSet.find(self.feature_set_id)
    end
    
  end
end
