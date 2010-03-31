module Freemium
  ## Adds 'manual billing' functionality to the Subscription class. Manual
  ## billing means that you are not using 'recurring billing' functionality
  ## of your payment processor. Instead you will run the 'run_billing' method
  ## each day, and freemium will make sure accounts get charged appropriately.
  ## You can call 'run_billing' from a cron job with this command:
  ## /PATH/TO/DEPLOYED/APP/script/runner -e production FreemiumSubscription.run_billing

  ## JCS: I'm not sure what's up with the instance variables in here. Maybe they should be local variables?
  module ManualBilling
    def self.included(base)
      base.extend ClassMethods
    end

    # Override if you need to charge something different than the rate (ex: yearly billing option)
    def installment_amount(options = {})
      self.rate(options)
    end

    # charges this subscription.
    # assumes, of course, that this module is mixed in to the Subscription model
    def charge!
      # Save the transaction immediately
      @transaction = Freemium.gateway.charge(billing_key, self.installment_amount)
      @transaction.credit_card = "#{self.credit_card.display_card_type} #{self.credit_card.display_number}"
      self.transactions << @transaction
      self.last_transaction_at = Time.now # TODO this could probably now be inferred from the list of transactions
      self.save(false)
    
      begin
        if @transaction.success?
          receive_payment!(@transaction)
          Freemium.mailer.deliver_payment_receipt(@transaction)
        elsif self.expired?
          Freemium.mailer.deliver_expiration_notice(self)
          self.expire!
        else 
          start_grace_period!(@transaction) unless self.in_grace?
          Freemium.mailer.deliver_expiration_warning(self)
        end
          
      rescue StandardError => e
        logger.error "(#{ e.class }) #{ e } in ManualBilling charge!"
        HoptoadNotifier.notify(e)
      end
      
      @transaction
    end

    module ClassMethods
      # the process you should run periodically
      def run_billing
        # charge all billable subscriptions
        @transactions = find_billable.collect do |billable|
          billable.charge!
        end

        # send the activity report
        Freemium.mailer.deliver_admin_report(
          @transactions # Add in transactions
        ) if Freemium.admin_report_recipients && !@transactions.empty?

        ## Warn users whose free trial is about to end
        find_warn_about_trial_ending.each do |subscription|
          Freemium.mailer.deliver_trial_ends_soon_warning(subscription)
          subscription.sent_trial_ends = true
          subscription.save!
          
        end
        
        @transactions
      end

      def bill_just_one
        find_billable.first.charge!
      end

      protected
      
      # a subscription is due on the last day it's paid through. so this finds all
      # subscriptions that expire the day *after* the given date. 
      # because of coupons we can't trust rate_cents alone and need to verify that the account is indeed paid?
      def find_billable
        self.paid.due.select{|s| s.paid? }
      end

      def find_warn_about_trial_ending
        self.paid.trial_ends_soon.scoped(:conditions => {:sent_trial_ends => false})
      end
    end
  end
end
