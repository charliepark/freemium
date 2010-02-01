# == Attributes
#   subscribable:         The model in your system that has the subscription. probably a User.
#   subscription_plan:    Which service plan this subscription is for. 
#   last_transaction_at:  Date the last gateway transaction was for this account. with 'recuring_billing' this is used by your gateway to find "new" transactions.
#   paid_through:         Date the subscription currently expires, assuming no further payment. for manual billing, this also determines when the next payment is due.
#   expires_on            Normally NULL. When an account is past due, expires_on will be set to the last day of the grace period
#   started_on:           Date that the user started their subscription. This is reset when the user changes SubscriptionPlans

module Freemium
  module Subscription
    include Rates
        
    def self.included(base)
      base.class_eval do
        belongs_to :subscription_plan, :class_name => "FreemiumSubscriptionPlan"
        belongs_to :subscribable, :polymorphic => true
        belongs_to :credit_card, :dependent => :destroy, :class_name => "FreemiumCreditCard"
        has_many :coupon_redemptions, :conditions => "freemium_coupon_redemptions.expired_on IS NULL", :class_name => "FreemiumCouponRedemption", :foreign_key => :subscription_id, :dependent => :destroy
        has_many :coupons, :through => :coupon_redemptions, :conditions => "freemium_coupon_redemptions.expired_on IS NULL"
  
        # Auditing
        has_many :transactions, :class_name => "FreemiumTransaction", :foreign_key => :subscription_id
              
        named_scope :paid, :include => [:subscription_plan], :conditions => "freemium_subscription_plans.rate_cents > 0"
        named_scope :due, lambda {
          {
            :conditions =>  ['paid_through <= ?', Date.today] # could use the concept of a next retry date
          }
        }

        named_scope :expired, lambda {
          {
            :conditions => ['expire_on >= paid_through AND expire_on <= ?', Date.today]
          }
       }

        named_scope :trial_ends_soon, lambda {
          {:conditions => ["in_trial = 1 AND paid_through <= ?", Date.today + 5.days]}
        }

        before_validation_on_create :start_free_trial
        before_validation :set_started_on
        
        after_create :audit_create
        after_update :audit_update
        after_destroy :audit_destroy
           
        ## JCS: This was modified to NOT validate subscribable on create. I did this because subscribable_id
        ## doesn't exist until after the models have been saved. I'm not sure how other people create this
        ## nest of associations with the validation as it was.
        validates_presence_of :subscribable, :unless => Proc.new {|s| s.new_record?}
        validates_associated :subscribable, :unless => Proc.new {|s| s.new_record?}
        validates_presence_of :subscription_plan
        validates_presence_of :paid_through, :if => :paid? 
        validates_presence_of :started_on
        validates_presence_of :credit_card, :if => :paid?
        validates_associated :credit_card, :if => :paid?
      end
      base.extend ClassMethods
    end
    
    def original_plan
      @original_plan ||= FreemiumSubscriptionPlan.find(self.changes["subscription_plan_id"].first) if subscription_plan_id_changed?
    end
    
    ##
    ## Callbacks
    ##
    
    protected
    
    def billing_key
      return self.credit_card ? self.credit_card.billing_key : nil
    end

    def start_free_trial
      if Freemium.days_free_trial && paid? 
        # paid + new subscription = in free trial
        self.paid_through = Date.today + Freemium.days_free_trial
        self.in_trial = true
      end
    end

    def set_started_on
      self.started_on = Date.today if subscription_plan_id_changed?
    end
    
    ##
    ## Callbacks :: Auditing
    ##    
    
    def audit_create
      FreemiumSubscriptionChange.create(:reason => "new", 
                                        :subscribable => self.subscribable,
                                        :new_subscription_plan_id => self.subscription_plan_id,
                                        :new_rate => self.rate,
                                        :original_rate => Money.empty)
    end
    
    def audit_update
      if self.subscription_plan_id_changed?
        return if self.original_plan.nil?
        reason = self.original_plan.rate > self.subscription_plan.rate ? (self.expired? ? "expiration" : "downgrade") : "upgrade"
        FreemiumSubscriptionChange.create(:reason => reason,
                                          :subscribable => self.subscribable,
                                          :original_subscription_plan_id => self.original_plan.id,
                                          :original_rate => self.rate(:plan => self.original_plan),
                                          :new_subscription_plan_id => self.subscription_plan.id,
                                          :new_rate => self.rate)
      end
    end
    
    def audit_destroy
      FreemiumSubscriptionChange.create(:reason => "cancellation", 
                                        :subscribable => self.subscribable,
                                        :original_subscription_plan_id => self.subscription_plan_id,
                                        :original_rate => self.rate,
                                        :new_rate => Money.empty)
    end
    
    public
    
    ##
    ## Class Methods
    ##
    
    module ClassMethods
      # expires all subscriptions that have been pastdue for too long (accounting for grace)
      def expire
        self.expired.select{|s| s.paid?}.each(&:expire!)
      end      
    end
    
    ##
    ## Rate
    ##
    
    def rate(options = {})
      options = {:date => Date.today, :plan => self.subscription_plan}.merge(options)
      
      return nil unless options[:plan]
      value = options[:plan].rate
      value = self.coupon(options[:date]).discount(value) if self.coupon(options[:date])
      value
    end
    
    def paid?
      return false unless rate
      rate.cents > 0
    end  
    
    ##
    ## Coupon Redemption
    ##
    
    def coupon_key=(coupon_key)
      @coupon_key = coupon_key ? coupon_key.downcase : nil
      self.coupon = FreemiumCoupon.find_by_redemption_key(@coupon_key) unless @coupon_key.blank?
    end
    
    def validate
      self.errors.add :coupon, "could not be found for '#{@coupon_key}'" if !@coupon_key.blank? && FreemiumCoupon.find_by_redemption_key(@coupon_key).nil?
    end
      
    def coupon=(coupon)
      if coupon
        s = FreemiumCouponRedemption.new(:subscription => self, :coupon => coupon)
        coupon_redemptions << s
      end
    end
    
    def coupon(date = Date.today)
      coupon_redemption(date).coupon rescue nil
    end

    def coupon_redemption(date = Date.today)
      return nil if coupon_redemptions.empty?
      active_coupons = coupon_redemptions.select{|c| c.active?(date)}
      return nil if active_coupons.empty?
      active_coupons.sort_by{|c| c.coupon.discount_percentage }.reverse.first
    end

    ##
    ## Remaining Time
    ##

    # returns the value of the time between now and paid_through.
    # will optionally interpret the time according to a certain subscription plan.
    def remaining_value(plan = self.subscription_plan)
      self.daily_rate(:plan => plan) * remaining_days
    end

    # if paid through today, returns zero
    def remaining_days
      self.paid_through - Date.today
    end

    ##
    ## Grace Period
    ##

    # if under grace through today, returns zero
    def remaining_days_of_grace
      self.expire_on - Date.today - 1
    end

    def in_grace?
      remaining_days < 0 and not expired?
    end

    ##
    ## Expiration
    ##

    # sets the expiration for the subscription based on today and the configured grace period.
    def expire_after_grace!(transaction = nil)
      return unless self.expire_on.nil? # You only set this once subsequent failed transactions shouldn't affect expiration
      self.expire_on = [Date.today, paid_through].max + Freemium.days_grace
      transaction.message = "now set to expire on #{self.expire_on}" if transaction
      Freemium.mailer.deliver_expiration_warning(self)
      save!
    end

    # sends an expiration email, then downgrades to a free plan
    def expire!
      Freemium.mailer.deliver_expiration_notice(self)
      # downgrade to a free plan
      self.expire_on = Date.today
      self.subscription_plan = Freemium.expired_plan
      # throw away this credit card (they'll have to start all over again)
      self.save!
    end

    def expired?
      expire_on and expire_on <= Date.today
    end
    
    ##
    ## Receiving More Money
    ##

    # receives payment and saves the record
    def receive_payment!(transaction)
      receive_payment(transaction)
      self.save!
    end

    # extends the paid_through period according to how much money was received.
    # when possible, avoids the days-per-month problem by checking if the money
    # received is a multiple of the plan's rate.
    #
    # really, i expect the case where the received payment does not match the
    # subscription plan's rate to be very much an edge case.
    def receive_payment(transaction)
      self.credit(transaction.amount)

      ## This exception is rescued silently somewhere, which is very bad.
      self.save!
      transaction.subscription.reload  # reloaded so that the paid_through date is correct

      transaction.message = "Paid through #{self.paid_through}"
      transaction.credited = true
      transaction.save!

      begin
        Freemium.mailer.deliver_payment_receipt(transaction)
      rescue Exception => e
        transaction.message = "Error sending payment receipt."
        HoptoadNotifier.notify(e)
      end
    end
    
    def credit(amount)
      self.paid_through = if amount.cents % rate.cents == 0
        self.paid_through + (amount.cents / rate.cents).months
      else
        self.paid_through + (amount.cents / daily_rate.cents).days
      end 
      
      # if they've paid again, then reset expiration
      self.expire_on = nil
      self.in_trial = false      
    end

  end
end
