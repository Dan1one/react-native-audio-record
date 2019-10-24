require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "RNAudioRecord"
  s.version      = package["version"]
  s.summary      = "Audio Record for UMP"
  s.homepage     = "https://github.com/react-native-community/react-native-audio-record"
  s.license      = "MIT"
  s.author       = { "Bryce Pavey" => "bryce@dreamwalk.com.au" }
  s.platform     = :ios, "9.0"
  s.source       = { :git => "git+http://deploy_account:test1234@git.dreamwalk.co/drodriguez/react-native-ump-bluetooth.git#master", :tag => "#{s.version}" }

  s.source_files  = "ios/**/*.{h,m,c}"

  s.dependency "React"
end
