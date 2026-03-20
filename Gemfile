source "https://rubygems.org"
ruby '3.2.10'

gem "fastlane", ">=2.232"
gem "abbrev"
gem "logger"
gem "mutex_m"
gem "csv"
gem "bigdecimal"
gem "base64"
gem "ostruct"
gem "nkf"
gem "sentry"

plugins_path = File.join(File.dirname(__FILE__), 'fastlane', 'Pluginfile')
eval_gemfile(plugins_path) if File.exist?(plugins_path)
