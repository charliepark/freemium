module Freemium
  class CreditCardStorageError < RuntimeError; end

  class << self
    # Lets you configure which ActionMailer class contains appropriate
    # mailings for invoices, expiration warnings, and expiration notices.
    # You'll probably want to create your own, based on lib/subscription_mailer.rb.
    attr_writer :mailer
    def mailer
      @mailer ||= SubscriptionMailer
    end

    # The gateway of choice. Default gateway is a stubbed testing gateway.
    attr_writer :gateway
    def gateway
      @gateway ||= Freemium::Gateways::Test.new
    end

    # You need to specify whether Freemium or your gateway's ARB module will control
    # the billing process. If your gateway's ARB controls the billing process, then
    # Freemium will simply try and keep up-to-date on transactions.
    def billing_handler=(val)
      case val
        when :manual:   FreemiumSubscription.send(:include, Freemium::ManualBilling)
        when :gateway:  FreemiumSubscription.send(:include, Freemium::RecurringBilling)
        else raise "unknown billing_handler: #{val}"
      end
    end

    # How many days to keep an account active after it fails to pay.
    attr_writer :days_grace
    def days_grace
      @days_grace ||= 3
    end
    
    # How many days in an initial free trial?
    attr_writer :days_free_trial
    def days_free_trial
      @days_free_trial ||= 0
    end    

    # What plan to assign to subscriptions that have expired. May be nil.
    attr_writer :expired_plan
    def expired_plan
      unless @expired_plan 
        @expired_plan =   FreemiumSubscriptionPlan.find_by_key(expired_plan_key.to_s) unless expired_plan_key.nil?
        @expired_plan ||= FreemiumSubscriptionPlan.find(:first, :conditions => "rate_cents = 0")
      end
      @expired_plan
    end

    # It's easier to assign a plan by it's key (so you don't get errors before you run migrations)
    attr_accessor :expired_plan_key

    # If you want to receive admin reports, enter an email (or list of emails) here.
    # These will be bcc'd on all SubscriptionMailer emails, and will also receive the
    # admin activity report.
    attr_accessor :admin_report_recipients

    attr_writer :logger
    def logger
      @logger ||= Rails.logger
    end
  end

end
