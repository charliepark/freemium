class MoveBillingKeyFromSubscriptionToCreditCard < ActiveRecord::Migration
  def self.up
    ## Earlier versions of freemium had the billing_key (that is the token that
    ## is used to reference a credit card number stored with the Processor) in the
    ## subscription model rather than the credit_card model, which I thought was
    ## pretty weird. It makes it challenging to create an interface for the user
    ## to update their credit card information. This migration moves the billing_key
    ## to the credit_card model.

    add_column :freemium_credit_cards, :billing_key, :string
    add_index :freemium_credit_cards, :billing_key

    ## Copy the billing_keys from the freemium_subscriptions table to the 
    ## freemium_credit_cards table across the foreign key
    execute <<-SQL
    UPDATE freemium_credit_cards, freemium_subscriptions 
      SET freemium_credit_cards.billing_key = freemium_subscriptions.billing_key 
      WHERE freemium_credit_cards.id = freemium_subscriptions.credit_card_id
    SQL

    remove_column :freemium_subscriptions, :billing_key
  end

  def self.down
    add_column :freemium_subscriptions, :billing_key, :string
    add_index :freemium_subscriptions, :billing_key

    execute <<-SQL
    UPDATE freemium_subscriptions , freemium_credit_cards
      SET freemium_subscriptions.billing_key = freemium_credit_cards.billing_key
      WHERE freemium_credit_cards.id = freemium_subscriptions.credit_card_id
    SQL

    remove_column :freemium_credit_cards, :billing_key
  end
end
 
