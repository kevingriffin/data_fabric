# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = "gem-open"
  s.version = "0.1.6"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Nando Vieira"]
  s.date = "2011-05-10"
  s.description = "Open gems on your favorite editor by running a specific gem command like `gem open nokogiri`."
  s.email = ["fnando.vieira@gmail.com"]
  s.homepage = "http://rubygems.org/gems/gem-open"
  s.require_paths = ["lib"]
  s.rubygems_version = "1.8.23"
  s.summary = "Open gems on your favorite editor by running a specific gem command like `gem open nokogiri`."

  if s.respond_to? :specification_version then
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_development_dependency(%q<mocha>, ["~> 0.9.12"])
      s.add_development_dependency(%q<test-unit>, ["~> 2.3.0"])
    else
      s.add_dependency(%q<mocha>, ["~> 0.9.12"])
      s.add_dependency(%q<test-unit>, ["~> 2.3.0"])
    end
  else
    s.add_dependency(%q<mocha>, ["~> 0.9.12"])
    s.add_dependency(%q<test-unit>, ["~> 2.3.0"])
  end
end
