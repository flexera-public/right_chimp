# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "right_chimp/version"

Gem::Specification.new do |s|
  s.name        = "right_chimp"
  s.license = 'MIT'

  s.version     = Chimp::VERSION
  s.authors     = ["RightScale Operations"]
  s.email       = ["ops@rightscale.com"]
  s.homepage    = "https://github.com/rightscale/right_chimp"
  s.summary     = %q{RightScale platform command-line tool}
  s.description = %q{The Chimp is a tool for managing servers using the RightScale platform.}

  # s.rubyforge_project = "chimp"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency "rake", "~> 0.9.2.2"
  s.add_dependency "nokogiri", "~> 1.5.9"
  s.add_dependency "progressbar", "~> 0.11.0"
  s.add_dependency "right_api_client", "> 1.5"
  s.add_dependency "highline", "~> 1.7.2"

  s.add_development_dependency "rspec", "~> 2.6.0"
end
