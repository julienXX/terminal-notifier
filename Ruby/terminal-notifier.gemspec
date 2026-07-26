# frozen_string_literal: true

plist = File.expand_path('../Terminal Notifier/Terminal Notifier-Info.plist', __dir__)
# Also run on non-macOS machines, otherwise bundle installs directly from the repo will fail.
# version = `/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '#{plist}'`.strip
version = File.read(plist).match(%r{<string>(\d+\.\d+\.\d+)</string>})[1]

Gem::Specification.new do |gem|
  gem.name             = 'terminal-notifier'
  gem.version          = version
  gem.summary          = 'Send User Notifications on macOS 10.10 or higher.'
  gem.authors          = ['Eloy Duran', 'Julien Blanchard']
  gem.email            = ['eloy.de.enige@gmail.com', 'julien@sideburns.eu']
  gem.homepage         = 'https://github.com/julienXX/terminal-notifier'
  gem.license          = 'MIT'
  gem.required_ruby_version = '>= 3.2'

  gem.executables      = ['terminal-notifier']
  gem.files            = ['bin/terminal-notifier', 'lib/terminal-notifier.rb',
                          'lib/terminal-notifier/cli.rb'] + Dir.glob('vendor/terminal-notifier/**/*')
  gem.require_paths    = ['lib']

  gem.extra_rdoc_files = ['README.markdown']

  gem.metadata['rubygems_mfa_required'] = 'true'
end
