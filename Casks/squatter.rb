cask "squatter" do
  version "0.1.1"
  sha256 "c5c435a3abe19af23d0eeb9dec31fd63ba026d5bfac8634b65a5359ba6a6954f"

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
