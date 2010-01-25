module Freemium

  ## credited: A boolean that should be set to 'true' for successful transactions after the subscription has been updated to reflect the new paid_through date

  ## A transaction is created for ever intereaction with the payment processor.
  module Transaction
    
    def self.included(base)
      base.class_eval do
        attr_accessible :billing_key, :amount, :message, :success, :transactionid

        named_scope :since, lambda { |time| {:conditions => ["created_at >= ?", time]} }
        
        belongs_to :subscription, :class_name => "FreemiumSubscription"
        
        composed_of :amount, :class_name => 'Money', :mapping => [ %w(amount_cents cents) ], :allow_nil => true        
      end
    end

  end
end
