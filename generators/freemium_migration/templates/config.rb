# Sample configuration, but this will get you bootstrapped with BrainTree
# TODO:
# - information on where to register...
# - setting up production passwords...
# - better way to do production/test changes?
 
Freemium.gateway = Freemium::Gateways::BrainTree.new
Freemium.gateway.username = "demo"
Freemium.gateway.password = "password"
 
## If you want Freemium to take care of the billing itself
## (ie, handle everything within your app, with recurring payments via cron
## or some other batch job) use :manual .
##
## If you want to use the gateways recuring payment system use :gateway
Freemium.billing_handler = :manual
 
## The class name of mailer used to send out emails to subscriber. You will
## want to create your own mailer following the format of the included
## SubscriptionMailer.
Freemium.mailer = SubscriptionMailer
 
# uncomment to be cc'ed on all freemium emails that go out to the user
#Freemium.admin_report_recipients = %w{admin@site.com}
 
## The grace period is the number of days an account can be past due
## before it is marked as 'expired'. The grace period starts on the 
## first day that the account is not billed successfully. Defaults to
## zero. 
Freemium.days_grace = 3
 
## Would you like to offer a free trial? Change this to specify the
## length of the trial. Defaults to 0 days.
Freemium.days_free_trial = 30

## When a subscription expires, what should it's plan be set to?
## I recommened you make a plan named "expired".
# Freemium.expired_plan_key = "expired"
 
##### See vendor/plugins/freemium/freemium.rb for additional choices
 
if RAILS_ENV == 'production'
  # put your production password information here....
  Freemium.gateway.username = "demo"
  Freemium.gateway.password = "password"
elsif RAILS_ENV == 'test'
  # prevents you from calling BrainTree during your tests
  Freemium.gateway = Freemium::Gateways::Test.new
end
