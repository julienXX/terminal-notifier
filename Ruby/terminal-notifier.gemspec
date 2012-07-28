# -*- encoding: utf-8 -*-
plist = File.expand_path('../../Terminal Notifier/Terminal Notifier-Info.plist', __FILE__)
version = `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '#{plist}'`.strip

Gem::Specification.new do |gem|
  gem.name             = "terminal-notifier"
  gem.version          = version
  gem.summary          = 'Send User Notifications on Mac OS X 10.8.'
  gem.authors          = ["Eloy Duran"]
  gem.email            = ["eloy.de.enige@gmail.com"]
  gem.homepage         = 'https://github.com/alloy/terminal-notifier'

  gem.files            = ['lib/terminal-notifier.rb'] + Dir.glob('vendor/terminal-notifier/**/*')
  gem.require_paths    = ['lib']

  gem.extra_rdoc_files = ['README.markdown']
end
