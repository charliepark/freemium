## Preamble

*This branch of Freemium is not guaranteed to work. In fact, there's a good chance it doesn't. Please feel free to patch any obvious errors you see, but I would recommend NOT using this as the basis of your own branch.*

**Actually, yeah. Don't use this code for now.**

## Freemium

Freemium was written by Lance Ivy in an attempt to "encapsulate the Right Way to offer service subscriptions."



This version is a tweak of the copy maintained by ExpanDrive for use on their Strongspace service. This copy was adjusted by Charlie Park.

## Gateway Requirements

Rule #1: You never want to store credit card numbers yourself. This means that you need a gateway that either provides Automated Recurring Billing (ARB - a common offering) or credit card storage (e.g. TrustCommerce's Citadel).

Freemium will work with any gateway that provides credit card storage (the preferred method!), but it will not work with every gateway that provides ARB. Just because your gateway provides ARB doesn't mean that your application can fire-and-forget; you still needs to know about successful transactions (to send invoices) and failed transactions (to send warnings and/or expire a subscription). In order for your _application_ to know about these events without your intervention, the ARB module either needs to send event notifications or it needs to provide an API to retrieve and review recent transactions.

Freemium will only work with ARB modules that provide an API to retrieve and review recent transactions. This is by far the safest route, since most gateways only send email notifications that must be manually processed by a human (ugh!) and the others can have unreliable event notification systems (e.g. PayPal, see http://talklikeaduck.denhaven2.com/articles/2007/09/02/how-to-cure-the-paypal-subscription-blues). And in any case, ARB modules that send event notifications hardly ever tell you about successful transactions, so you still have to keep track of the periodic cycles so you can send invoices, which makes the whole ARB thing barely useful.

So what we really need is a list of known good and known bad gateways. The list below is just the beginning, off the top of my head.

### Good Gateways:

* TrustCommerce with Citadel (can use Citadel and/or ARB)

* Braintree Payment Solutions (SecureVault, or ARB)

### Probably Good Gateways:

* Authorize.net (CIM, or ARB if they also offer transaction review API)

### Bad Gateways:

* LoudCommerce's LinkPoint (no storage, and no transaction review)

# Expiration

I've tried to build Freemium with the understanding that sometimes a cron task might not run, and if that happens the customers should not get screwed. That means, for example, not expiring a customer account just because a billing process didn't run. So the process for expiring a subscription is as follows: the first nightly billing process that runs _after_ a subscription's last paid day will set the final expiration date of that subscription. The final expiration date will be calculated as a certain number of days (the grace period) after the date of the billing process (grace begins when the program _knows_ the account is pastdue). The first billing process that runs on or after the expiration date will then actually expire the subscription.

So there's some possible slack in the timeline. Suppose a subscription is paid through the 14th and there's a 2 day grace period. That means if a billing process runs on the 13th, then not until the 15th, the subscription will be set to expire on the 17th - the subscriber gets an extra day of grace because your billing process didn't run.

# Misc
* If there's no grace period then the same billing process will both set the expiration date and then actually expire the subscription, thanks to the order of events.
* Expiring a subscription means downgrading it to a free plan (if any) or removing the plan altogether.

# Install

0) Copy the plugin to your local computer. Also, make sure the Money plugin is on your machine.

  > script/plugin install git://github.com/charliepark/freemium.git
  > gem install money

1) Generate and run the migration:

  > ./script/generate freemium_migration

  > rake db:migrate

2) Populate the database with your subscription plan (create a migration to create SubscriptionPlan records).

  > ./script/generate migration populate_subscription_plans

Then populate that migration with something like the following:

  > def self.up

  >  SubscriptionPlan.create(:name => "comped", :rate_cents => 0)

  >  SubscriptionPlan.create(:name => "expired", :rate_cents => 0)

  >  SubscriptionPlan.create(:name => "monthly_1000", :rate_cents => 1000)

  >end

  >

  >def self.down

  >  SubscriptionPlan.delete_all

  >end

Note that I included the :rate_cents value in the name of the plan. You might want to _not_ include that, as it limits your flexibility. Since new subscription plans can be added easily, I'm comfortable with including the rate within the name, to make it less ambiguous when I'm calling and setting values within the program.

3) Create config/initializers/freemium.rb and configure at least the following:

  gateway         pick one, then see rdoc for your gateway's options to see what needs to be configured (api key, etc.)

  billing_control set to :full or :arb, depending on whether you're using your gateway's ARB module

  grace period    in days, zero days grace is ok

  mailer          for customized invoices, etc.

4) Create a SignupController (or similar) that does whatever it takes to get a unique billing key. This means you will have to get the credit card information from the user, create a CreditCard object, and save the object. Saving the CreditCard will activate a callback  that stores the credit card information with your payment processor. The corresponding billing_key will be stored in your database as a part of the CreditCard object.

5) Create association from your User model (or whatever) to the Subscription model.

6) Add a before_filter (or other logic) to properly enforce your premium plan. The filter should check that the User has an active Subscription to a SubscriptionPlan of the appropriate type.

7) Add `/PATH/TO/DEPLOYED/APP/script/runner -e production FreemiumSubscription.run_billing' to a daily cron task.

8) Tell me how any of this could be improved. I want this plugin to make freemium billing dead-simple.

Copyright (c) 2007 Lance Ivy, released under the MIT license
