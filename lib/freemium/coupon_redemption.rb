module Freemium
  module CouponRedemption
    
    def self.included(base)
      base.class_eval do
        belongs_to :subscription, :class_name => "FreemiumSubscription"
        belongs_to :coupon, :class_name => "FreemiumCoupon"

        attr_accessible :coupon, :subscription
        
        before_create :set_redeemed_on
        
        validates_presence_of :coupon
        validates_presence_of :subscription
        validates_uniqueness_of :coupon_id, :scope => :subscription_id, :message => "has already been applied"   
      end
    end

    def expire!
      self.update_attribute :expired_on, Date.today
    end  
    
    def active?(date = Date.today)
      expires_on ? date <= self.expires_on : true
    end
    
    def expires_on
      return nil unless self.coupon.duration_in_months
      self.redeemed_on + self.coupon.duration_in_months.months
    end
    
    def redeemed_on
      self['redeemed_on'] || Date.today
    end
    
    protected
    
    def set_redeemed_on
      self.redeemed_on = Date.today
    end
    
    def validate_on_create
      errors.add :subscription,  "must be paid"             if self.subscription && !self.subscription.subscription_plan.paid?
      errors.add :coupon,  "has expired"                    if self.coupon && (self.coupon.expired? || self.coupon.expired?)  
      errors.add :coupon,  "is not valid for selected plan" if self.coupon && self.subscription && !self.coupon.applies_to_plan?(self.subscription.subscription_plan)
    end    
              
  end
end
