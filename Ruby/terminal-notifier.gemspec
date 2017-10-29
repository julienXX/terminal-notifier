# -*- encoding: utf-8 -*-
plist = File.expand_path('../../Terminal Notifier/Terminal Notifier-Info.plist', __FILE__)
# Also run on non-OSX machines, otherwise bundle installs directly from the repo will fail.
# version = `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '#{plist}'`.strip
version = File.read(plist).match(%r{<string>(\d+\.\d+\.\d+)</string>})[1]


Gem::Specification.new do |gem|
  gem.name             = "terminal-notifier"
  gem.version          = version
  gem.summary          = 'Send User Notifications on macOS 10.10 or higher.'
  gem.authors          = ["Eloy Duran", "Julien Blanchard"]
  gem.email            = ["eloy.de.enige@gmail.com", "julien@sideburns.eu"]
  gem.homepage         = 'https://github.com/julienXX/terminal-notifier'
  gem.license          = 'MIT'

  gem.executables      = ['terminal-notifier']
  gem.files            = ['bin/terminal-notifier', 'lib/terminal-notifier.rb'] + Dir.glob('vendor/terminal-notifier/**/*')
  gem.require_paths    = ['lib']

  gem.extra_rdoc_files = ['README.markdown']

  gem.add_development_dependency 'bacon'
  gem.add_development_dependency 'mocha'
  gem.add_development_dependency 'mocha-on-bacon'
end
