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
      self.transactions << @transaction
      self.last_transaction_at = Time.now # TODO this could probably now be inferred from the list of transactions
      self.save(false)
    
      begin
        if @transaction.success? 
          receive_payment!(@transaction)
        elsif !@transaction.subscription.in_grace?
          expire_after_grace!(@transaction)
        end
      rescue Exception => e
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

        # actually expire any subscriptions whose time has come
        expire

        # send the activity report
        Freemium.mailer.deliver_admin_report(
          @transactions # Add in transactions
        ) if Freemium.admin_report_recipients && !@transactions.empty?
        
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
        self.paid.due.select{|s| s.paid?}
      end
    end
  end
end
