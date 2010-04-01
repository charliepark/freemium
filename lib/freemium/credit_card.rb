# == Attributes
#   billing_key: the id for this user in the remote billing gateway. may not exist if user is on a free plan.
#   card_type: the issuing credit card company, can be assigned automatically from the credit card number
#   display_number: The last four digits of the credit card number, stored as "XXX-XXX-XXX-NNNN" automatically when a number is assigned to self.number
#   expiration_date: the credit card expiration date
#   zip_code: the credit card zip code

module Freemium
  module CreditCard

    CARD_COMPANIES = { 
      'visa'               => /^4\d{12}(\d{3})?$/,
      'master'             => /^(5[1-5]\d{4}|677189)\d{10}$/,
      'discover'           => /^(6011|65\d{2})\d{12}$/,
      'american_express'   => /^3[47]\d{13}$/,
      'diners_club'        => /^3(0[0-5]|[68]\d)\d{11}$/,
      'jcb'                => /^3528\d{12}$/,
      'switch'             => /^6759\d{12}(\d{2,3})?$/,  
      'solo'               => /^6767\d{12}(\d{2,3})?$/,
      'dankort'            => /^5019\d{12}$/,
      'maestro'            => /^(5[06-8]|6\d)\d{10,17}$/,
      'forbrugsforeningen' => /^600722\d{10}$/,
      'laser'              => /^(6304[89]\d{11}(\d{2,3})?|670695\d{13})$/
    }

    DISPLAY_COMPANIES = {
      'visa'               => 'Visa',
      'master'             => 'MasterCard',
      'discover'           => 'Discover Card',
      'american_express'   => 'American Express',
      'diners_club'        => 'Diners Club',
      'jcb'                => 'JCB Card',
      'switch'             => 'Switch Card',
      'solo'               => 'SOLO',
      'dankort'            => 'Dankort',
      'maestro'            => 'Maestro',
      'forbrugsforeningen' => 'Forbrugsforeningen',
      'laser'              => 'Laser'
    }

    def self.included(base)
      base.class_eval do
        # Essential attributes for a valid, non-bogus creditcards
        attr_reader :number
        attr_accessor :first_name, :last_name

        # Required for Switch / Solo cards
        attr_accessor :start_month, :start_year, :issue_number

        # Optional verification_value (CVV, CVV2 etc). Gateways will try their best to 
        # run validation on the passed in value if it is supplied
        attr_accessor :verification_value
                
        attr_accessible :number, :month, :year, :first_name, :last_name, :start_month, :start_year, :issue_number, :verification_value, :card_type, :zip_code       
                
        has_one :subscription, :class_name => "FreemiumSubscription"
        
        before_validation :sanitize_data, :if => :changed?
        before_save :store_credit_card_offsite
        before_destroy :cancel_in_remote_system

        def number=(new_number)
          @number = new_number.to_s.gsub(/[^\d]/, "")
          self.card_type = self.class.card_type?(number)
        end

        def month
          return @month if @month
          return expiration_date.month if expiration_date
          return nil
        end

        def month=(new_month)
          @month = new_month.to_i
        end

        def year
          return @year if @year
          return expiration_date.year if expiration_date
          return nil
        end
    
        def year=(new_year)
          @year = new_year.to_i
          @year = @year + 2000 if @year < 100
        end

      end
      
      base.extend(ClassMethods)
    end

    ##
    ## Callbacks
    ##
    
    protected
    
    def sanitize_data #:nodoc: 
      self.set_expiration_date(year, month) if @year 
      self.card_type.downcase! if card_type.respond_to?(:downcase)
    end

    def set_expiration_date(year, month)
      self['expiration_date'] = Date.strptime("#{year}-#{month}", '%Y-%m') + 1.month - 1.day
    end

    # Because of the third-party interaction with the gateway, you
    # need to be careful to only use this method when you expect to
    # be able to save the record successfully. Otherwise you may end
    # up storing a credit card in the gateway and then losing the key.
    def store_credit_card_offsite
      if self.changed? && self.valid?

        ## If this CreditCard object already has a billing_key, then 
        ## delete it at the payment processor before getting a new one.
        cancel_in_remote_system

        response = billing_key ? Freemium.gateway.update(billing_key, self, self.address) : Freemium.gateway.store(self, self.address)
        raise Freemium::CreditCardStorageError.new(response.message) unless response.success?
        self.billing_key = response.billing_key
      end
    end
    
    def discard_credit_card_unless_paid
      unless subscription.paid?
        cancel_in_remote_system
        self.destroy
      end
    end

    def cancel_in_remote_system
      if billing_key
        Freemium.gateway.cancel(self.billing_key)
        self.billing_key = nil
      end
    end
    
    public
    
    ##
    ## Class Methods
    ##
    
    module ClassMethods
      # Returns true if it validates. Optionally, you can pass a card type as an argument and 
      # make sure it is of the correct type.
      #
      # References:
      # - http://perl.about.com/compute/perl/library/nosearch/P073000.htm
      # - http://www.beachnet.com/~hstiles/cardtype.html
      def valid_number?(number)
        valid_card_number_length?(number) && 
          valid_checksum?(number)
      end
      
      # Regular expressions for the known card companies.
      # 
      # References: 
      # - http://en.wikipedia.org/wiki/Credit_card_number 
      # - http://www.barclaycardbusiness.co.uk/information_zone/processing/bin_rules.html 
      def card_companies
        CARD_COMPANIES
      end
      
      # Returns a string containing the type of card from the list of known information below.
      # Need to check the cards in a particular order, as there is some overlap of the allowable ranges
      #--
      # TODO Refactor this method. We basically need to tighten up the Maestro Regexp. 
      # 
      # Right now the Maestro regexp overlaps with the MasterCard regexp (IIRC). If we can tighten 
      # things up, we can boil this whole thing down to something like... 
      # 
      #   def type?(number)
      #     return 'visa' if valid_test_mode_card_number?(number)
      #     card_companies.find([nil]) { |type, regexp| number =~ regexp }.first.dup
      #   end
      # 
      def card_type?(number)
        card_companies.reject { |c,p| c == 'maestro' }.each do |company, pattern|
          return company.dup if number =~ pattern 
        end
        
        return 'maestro' if number =~ card_companies['maestro']

        return nil
      end
      
      def last_digits(number)     
        number.to_s.length <= 4 ? number : number.to_s.slice(-4..-1) 
      end
      
      # Checks to see if the calculated type matches the specified type
      def matching_card_type?(number, card_type)
        card_type?(number) == card_type
      end      
      
      private
      
      def valid_card_number_length?(number) #:nodoc:
        number.to_s.length >= 12
      end
      
      # Checks the validity of a card number by use of the the Luhn Algorithm. 
      # Please see http://en.wikipedia.org/wiki/Luhn_algorithm for details.
      def valid_checksum?(number) #:nodoc:
        sum = 0
        for i in 0..number.length
          weight = number[-1 * (i + 2), 1].to_i * (2 - (i % 2))
          sum += (weight < 10) ? weight : weight - 9
        end
        
        (number[-1,1].to_i == (10 - sum % 10) % 10)
      end

    end

    def expired?
      return false unless expiration_date
      Date.today > expiration_date
    end
    
    ##
    ## From ActiveMerchant::Billing::CreditCard
    ##    
    
    def name?
      first_name? && last_name?
    end
    
    def first_name?
      !@first_name.blank?
    end
    
    def last_name?
      !@last_name.blank?
    end
          
    def name
      "#{@first_name} #{@last_name}"
    end

    def number=(new_number)
      @number = new_number
      ## Also update the display number
      write_attribute(:display_number, self.class.last_digits(number))
    end

    def display_card_type
      DISPLAY_COMPANIES[card_type]
    end

    def last_digits
      self.class.last_digits(number)
    end
    
    def address
      unless @address
        @address = Address.new
        @address.zip = self.zip_code
      end
      @address
    end
    
    class Address  
      attr_accessor :email, :street, :city, :state, :zip, :country
    end    
    
    ##
    ## Overrides
    ##
    
    # We're overriding AR#changed? to include instance vars that aren't persisted to see if a new card is being set
    def changed?
      card_type_changed? || 
      @year || @month ||
      [:number, :first_name, :last_name, :start_month, :start_year, :issue_number, :verification_value].select{|attr| !self.send(attr).blank?}.first # 'first' returns nil if the array is empty
    end

    ##
    ## Validation
    ##
    
    def validate
      return if !changed?
      
      validate_essential_attributes

      # Bogus card is pretty much for testing purposes. Lets just skip these extra tests if its used
      return if card_type == 'bogus'

      validate_card_type
      validate_card_number
      validate_switch_or_solo_attributes
    end
    
    private
    
    def validate_card_number #:nodoc:
      errors.add :number, "is not a valid credit card number" unless self.class.valid_number?(number)
      unless errors.on(:number) || errors.on(:type)
        errors.add :card_type, "is not the correct card type" unless self.class.matching_card_type?(number, card_type)
      end
    end
    
    def validate_card_type #:nodoc:
      errors.add :card_type, "is required" if card_type.blank?
      errors.add :card_type, "is invalid"  unless self.class.card_companies.keys.include?(card_type)
    end
    
    def validate_essential_attributes #:nodoc:
      errors.add :first_name, "cannot be empty"      if @first_name.blank?
      errors.add :last_name,  "cannot be empty"      if @last_name.blank?
      errors.add :month,      "is not a valid month" unless valid_month?(@month)
      errors.add :year,       "expired"              if expired?
      errors.add :year,       "is not a valid year"  unless valid_expiration_year?(@year)
    end
    
    def validate_switch_or_solo_attributes #:nodoc:
      if %w[switch solo].include?(card_type)
        unless valid_month?(@start_month) && valid_start_year?(@start_year) || valid_issue_number?(@issue_number)
          errors.add :start_month,  "is invalid"      unless valid_month?(@start_month)
          errors.add :start_year,   "is invalid"      unless valid_start_year?(@start_year)
          errors.add :issue_number, "cannot be empty" unless valid_issue_number?(@issue_number)
        end
      end
    end
    
    def valid_month?(month)
      (1..12).include?(month)
    end
    
    def valid_expiration_year?(year)
      (Time.now.year..Time.now.year + 20).include?(year)
    end
    
    def valid_start_year?(year)
      year.to_s =~ /^\d{4}$/ && year.to_i > 1987
    end
    
    def valid_issue_number?(number)
      number.to_s =~ /^\d{1,2}$/
    end    
    
  end
end
