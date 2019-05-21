# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'atomic_swap/version'

Gem::Specification.new do |spec|
  spec.name          = "atomic_swap"
  spec.version       = AtomicSwap::VERSION
  spec.authors       = ["Pradeep Chaturvedi"]
  spec.email         = ["pradeep.chaturvedi97@gmail.com"]
  spec.summary       = %q{atomic swaps }
  spec.description   = %q{Ruby based Bitcoin swaps}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_dependency "bitcoin-ruby", "~> 0.0", ">= 0.0.6"
  spec.add_dependency "ffi", "~> 1.9"
end
