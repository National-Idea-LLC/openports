cask "squatter" do
  version "0.1.0"
  sha256 "82b34bd383a432d8064c6c84e7000012419bad30bd255378751c0ace9b18249a"

  url "https://github.com/National-Idea-LLC/squatter/releases/download/v#{version}/Squatter-#{version}.dmg",
      verified: "github.com/National-Idea-LLC/squatter/"
  name "Squatter"
  desc "Menu bar app that shows which process is listening on each port"
  homepage "https://github.com/National-Idea-LLC/squatter"

  depends_on macos: ">= :sequoia"

  app "Squatter.app"

  zap trash: [
    "~/Library/Preferences/sa.ni.squatter.plist",
  ]
end
