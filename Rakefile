require 'rubygems'
require 'bundler/gem_tasks'

desc "Open an irb session preloaded with Chimp"
task :console do
  sh "irb -rubygems -I lib -r lib/right_chimp.rb"
end

desc "Run rspec tests"
task :spec do
  sh "rspec spec/spec_*.rb"
end

desc "Clean up source directories and packages"
task :clean do
  sh "rm -rf pkg/*.gem 2>/dev/null || true"
  sh "rm *~ */*~ */*/*~ 2>/dev/null || true"
end
