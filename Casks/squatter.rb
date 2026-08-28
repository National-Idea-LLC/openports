cask "squatter" do
  version "0.1.0"
  sha256 :no_check # replaced with the release DMG checksum at publish time

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
