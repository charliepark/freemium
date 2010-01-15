require File.dirname(__FILE__) + '/../test_helper'

class SubscriptionTest < ActiveSupport::TestCase
  fixtures :users, :freemium_subscriptions, :freemium_subscription_plans, :freemium_credit_cards

  def test_creating_free_subscription
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:free))
    subscription.save!
    
    assert !subscription.new_record?, subscription.errors.full_messages.to_sentence
    assert_equal Date.today, subscription.reload.started_on
    assert_equal false, subscription.in_trial?
    assert_nil subscription.paid_through
    assert !subscription.paid?
    
    assert_changed(subscription.subscribable, :new, nil, freemium_subscription_plans(:free))
  end
  
  def test_creating_paid_subscription
    Freemium.days_free_trial = 30
  
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:basic), :credit_card => FreemiumCreditCard.sample)
    subscription.save!

    assert !subscription.new_record?, subscription.errors.full_messages.to_sentence
    assert_equal Date.today, subscription.reload.started_on
    assert_equal true, subscription.in_trial?
    assert_not_nil subscription.paid_through
    assert_equal Date.today + Freemium.days_free_trial, subscription.paid_through
    assert subscription.paid?
    assert_not_nil subscription.billing_key
    
    assert_changed(subscription.subscribable, :new, nil, freemium_subscription_plans(:basic))
  end  
  
  def test_upgrade_from_free
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:free))
    subscription.save!
        
    new_date = Date.today + 10.days
    Date.stubs(:today).returns(new_date)
    
    assert_equal false, subscription.in_trial?
    subscription.subscription_plan = freemium_subscription_plans(:basic)
    subscription.credit_card = FreemiumCreditCard.sample 
    subscription.save!
    
    assert_equal new_date, subscription.reload.started_on
    assert_not_nil subscription.paid_through
    assert_equal false, subscription.in_trial?
    assert_equal new_date, subscription.paid_through
    assert subscription.paid?
    assert_not_nil subscription.billing_key    
    
    assert_changed(subscription.subscribable, :upgrade, freemium_subscription_plans(:free), freemium_subscription_plans(:basic))
  end
  
  def test_downgrade
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:basic), :credit_card => FreemiumCreditCard.sample)
    subscription.save!
    
    new_date = Date.today + 10.days
    Date.stubs(:today).returns(new_date)
    
    subscription.subscription_plan = freemium_subscription_plans(:free)
    subscription.save!
    
    assert_equal new_date, subscription.reload.started_on
    assert_nil subscription.paid_through
    assert !subscription.paid?
    assert_nil subscription.billing_key 
    assert_nil subscription.credit_card   
    
    assert_changed(subscription.subscribable, :downgrade, freemium_subscription_plans(:basic), freemium_subscription_plans(:free))
  end

  def test_associations
    assert_equal users(:bob), freemium_subscriptions(:bobs_subscription).subscribable
    assert_equal freemium_subscription_plans(:basic), freemium_subscriptions(:bobs_subscription).subscription_plan
  end

  def test_remaining_days
    assert_equal 20, freemium_subscriptions(:bobs_subscription).remaining_days
  end

  def test_remaining_value
    assert_equal Money.new(840), freemium_subscriptions(:bobs_subscription).remaining_value
  end

  ##
  ## Upgrade / Downgrade service credits
  ##

  def test_upgrade_credit
    subscription = freemium_subscriptions(:bobs_subscription)
    new_plan = freemium_subscription_plans(:premium)

    assert subscription.remaining_value.cents > 0
    expected_paid_through = Date.today + (subscription.remaining_value.cents / new_plan.daily_rate.cents)
    subscription.subscription_plan = freemium_subscription_plans(:premium)
    subscription.save!
    
    assert_equal expected_paid_through, subscription.paid_through
  end
  
  def test_upgrade_no_credit_for_free_trial
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:premium), :credit_card => FreemiumCreditCard.sample)
    subscription.save!
    
    assert_equal Date.today + Freemium.days_free_trial, subscription.paid_through
    assert_equal true, subscription.in_trial?
    
    subscription.subscription_plan = freemium_subscription_plans(:basic)
    subscription.save!
    
    assert_equal Date.today, subscription.paid_through
    assert_equal false, subscription.in_trial?
  end
  
  ##
  ## Validations
  ##

  def test_missing_fields
    [:subscription_plan, :subscribable].each do |field|
      subscription = build_subscription(field => nil)
      subscription.save
      
      assert subscription.new_record?
      assert subscription.errors.on(field)
    end
  end

  ##
  ## Receiving payment
  ##

  def test_receive_monthly_payment
    subscription = freemium_subscriptions(:bobs_subscription)
    paid_through = subscription.paid_through
    subscription.credit(freemium_subscription_plans(:basic).rate)
    subscription.save!
    assert_equal (paid_through >> 1).to_s, subscription.paid_through.to_s, "extended by one month"
    assert_not_nil subscription.transactions
  end

  def test_receive_quarterly_payment
    subscription = freemium_subscriptions(:bobs_subscription)
    paid_through = subscription.paid_through
    subscription.credit(freemium_subscription_plans(:basic).rate * 3)
    subscription.save!
    assert_equal (paid_through >> 3).to_s, subscription.paid_through.to_s, "extended by three months"
  end

  def test_receive_partial_payment
    subscription = freemium_subscriptions(:bobs_subscription)
    paid_through = subscription.paid_through
    subscription.credit(freemium_subscription_plans(:basic).rate * 0.5)
    subscription.save!
    assert_equal (paid_through + 15).to_s, subscription.paid_through.to_s, "extended by 15 days"
  end

  def test_receiving_payment_sends_payment_receipt
    subscription = freemium_subscriptions(:bobs_subscription)
    ActionMailer::Base.deliveries = []
    transaction = create_transaction_for(freemium_subscription_plans(:basic).rate, subscription)
    subscription.receive_payment!(transaction)
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  def test_receiving_payment_when_sending_payment_receipt_asplodes
    subscription = freemium_subscriptions(:bobs_subscription)
    paid_through = subscription.paid_through
    Freemium.mailer.expects(:deliver_invoice).raises(RuntimeError,"Failed")
    transaction = create_transaction_for(freemium_subscription_plans(:basic).rate, subscription)
    subscription.receive_payment!(transaction)
    subscription = subscription.reload
    assert_equal (paid_through >> 1).to_s, subscription.paid_through.to_s, "extended by one month"
  end

  ##
  ## Requiring Credit Cards ...
  ##

  def test_requiring_credit_card_for_pay_plan
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:premium))
    subscription.stubs(:credit_card).returns(nil)
    subscription.valid?
    
    assert subscription.errors.on(:credit_card)
  end

  def test_requiring_credit_card_for_free_plan
    subscription = build_subscription
    subscription.valid?
    
    assert !subscription.errors.on(:credit_card)
  end

  ##
  ## Expiration
  ##

  def test_instance_expire
    Freemium.expired_plan_key = :free
    Freemium.gateway.expects(:cancel).once.returns(nil)
    ActionMailer::Base.deliveries = []
    freemium_subscriptions(:bobs_subscription).expire!

    assert_equal 1, ActionMailer::Base.deliveries.size, "notice is sent to user"
    assert_equal freemium_subscription_plans(:free), freemium_subscriptions(:bobs_subscription).subscription_plan, "subscription is downgraded to free"
    assert_nil freemium_subscriptions(:bobs_subscription).billing_key, "billing key is thrown away"
    assert_nil freemium_subscriptions(:bobs_subscription).reload.billing_key, "billing key is thrown away"
    
    assert_changed(freemium_subscriptions(:bobs_subscription).subscribable, :expiration, freemium_subscription_plans(:basic), freemium_subscription_plans(:free))    
  end

  def test_class_expire
    Freemium.expired_plan_key = :free
    freemium_subscriptions(:bobs_subscription).update_attributes(:paid_through => Date.today - 4, :expire_on => Date.today)
    ActionMailer::Base.deliveries = []
    
    assert_equal freemium_subscription_plans(:basic), freemium_subscriptions(:bobs_subscription).subscription_plan
    
    FreemiumSubscription.expire
    
    assert_equal freemium_subscription_plans(:free), freemium_subscriptions(:bobs_subscription).reload.subscription_plan
    assert_equal Date.today, freemium_subscriptions(:bobs_subscription).reload.started_on
    assert ActionMailer::Base.deliveries.size > 0
    
    assert_changed(freemium_subscriptions(:bobs_subscription).subscribable, :expiration, freemium_subscription_plans(:basic), freemium_subscription_plans(:free)) 
  end

  def test_expire_after_grace_sends_warning
    ActionMailer::Base.deliveries = []
    freemium_subscriptions(:bobs_subscription).expire_after_grace!
    
    assert_equal 1, ActionMailer::Base.deliveries.size
  end
  
  def test_expire_after_grace
    assert_nil freemium_subscriptions(:bobs_subscription).expire_on
    freemium_subscriptions(:bobs_subscription).paid_through = Date.today - 2
    freemium_subscriptions(:bobs_subscription).expire_after_grace!
    
    assert_equal Date.today + Freemium.days_grace, freemium_subscriptions(:bobs_subscription).reload.expire_on
  end

  def test_expire_after_grace_with_remaining_paid_period
    freemium_subscriptions(:bobs_subscription).paid_through = Date.today + 1
    freemium_subscriptions(:bobs_subscription).expire_after_grace!
    
    assert_equal Date.today + 1 + Freemium.days_grace, freemium_subscriptions(:bobs_subscription).reload.expire_on
  end

  def test_grace_and_expiration
    assert_equal 3, Freemium.days_grace, "test assumption"

    subscription = FreemiumSubscription.new(:paid_through => Date.today + 5)
    assert !subscription.in_grace?
    assert !subscription.expired?

    # a subscription that's pastdue but hasn't been flagged to expire yet.
    # this could happen if a billing process skips, in which case the subscriber
    # should still get a full grace period beginning from the failed attempt at billing.
    # even so, the subscription is "in grace", even if the grace period hasn't officially started.
    subscription = FreemiumSubscription.new(:paid_through => Date.today - 5)
    assert subscription.in_grace?
    assert !subscription.expired?

    # expires tomorrow
    subscription = FreemiumSubscription.new(:paid_through => Date.today - 5, :expire_on => Date.today + 1)
    assert_equal 0, subscription.remaining_days_of_grace
    assert subscription.in_grace?
    assert !subscription.expired?

    # expires today
    subscription = FreemiumSubscription.new(:paid_through => Date.today - 5, :expire_on => Date.today)
    assert_equal -1, subscription.remaining_days_of_grace
    assert !subscription.in_grace?
    assert subscription.expired?
  end

  ##
  ## Deleting (possibly from a cascading delete, such as User.find(5).delete)
  ##

  def test_deleting_cancels_in_gateway
    Freemium.gateway.expects(:cancel).once.returns(nil)
    freemium_subscriptions(:bobs_subscription).destroy

    assert_changed(freemium_subscriptions(:bobs_subscription).subscribable, :cancellation, freemium_subscription_plans(:basic), nil)    
  end

  ##
  ## The Subscription#credit_card= shortcut
  ##
  def test_adding_a_credit_card
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:premium))
    cc = FreemiumCreditCard.sample
    response = Freemium::Response.new(true)
    response.billing_key = "alphabravo"
    Freemium.gateway.expects(:store).with(cc, cc.address).returns(response)

    subscription.credit_card = cc
    assert_nothing_raised do subscription.save! end
    assert_equal "alphabravo", subscription.billing_key
  end

  def test_updating_a_credit_card
    subscription = FreemiumSubscription.find(:first, :conditions => "billing_key IS NOT NULL")
    cc = FreemiumCreditCard.sample
    response = Freemium::Response.new(true)
    response.billing_key = "new code"
    Freemium.gateway.expects(:update).with(subscription.billing_key, cc, cc.address).returns(response)

    subscription.credit_card = cc
    assert_nothing_raised do subscription.save! end
    assert_equal "new code", subscription.billing_key, "catches any change to the billing key"
  end
  
  def test_updating_an_expired_credit_card
    subscription = FreemiumSubscription.find(:first, :conditions => "billing_key IS NOT NULL")    
    cc = FreemiumCreditCard.sample
    response = Freemium::Response.new(true)
    Freemium.gateway.expects(:update).with(subscription.billing_key, cc, cc.address).returns(response)

    subscription.expire_on = Time.now
    assert subscription.save
    assert_not_nil subscription.reload.expire_on

    subscription.credit_card = cc
    assert_nothing_raised do subscription.save! end
    assert_nil subscription.expire_on
    assert_nil subscription.reload.expire_on
  end  

  def test_failing_to_add_a_credit_card
    subscription = build_subscription(:subscription_plan => freemium_subscription_plans(:premium))
    cc = FreemiumCreditCard.sample
    response = Freemium::Response.new(false)
    Freemium.gateway.expects(:store).returns(response)
    
    subscription.credit_card = cc
    assert_raises Freemium::CreditCardStorageError do subscription.save! end
  end

  protected

  def build_subscription(options = {})
    FreemiumSubscription.new({
      :subscription_plan => freemium_subscription_plans(:free),
      :subscribable => users(:sue)
    }.merge(options))    
  end
  
  def create_transaction_for(amount, subscription)
    FreemiumTransaction.create :amount => amount, :subscription => subscription, :success => true, :billing_key => 12345
  end
  
  def assert_changed(subscribable, reason, original_plan, new_plan)
    changes = FreemiumSubscriptionChange.find(:all, :conditions => ["subscribable_id = ? AND subscribable_type = ?", subscribable.id, subscribable.class.to_s]).last
    assert_not_nil changes
    assert_equal reason.to_s, changes.reason
    assert_equal original_plan, changes.original_subscription_plan
    assert_equal new_plan, changes.new_subscription_plan
    assert_equal (original_plan ? original_plan.rate.cents : 0), changes.original_rate_cents
    assert_equal (new_plan ? new_plan.rate.cents : 0), changes.new_rate_cents
  end
  
end
