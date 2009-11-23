# depends on the Money gem
begin
  require 'money'
rescue LoadError
  puts "Freemium depends on the money gem: http://rubyforge.org/projects/money/"
  puts "maybe: gem install money"
end
