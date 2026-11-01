# Public (unsigned) Mac build

The free Mac download has no Apple signing, so Firebase Auth cannot use the Keychain (SecItemAdd -34018).
`tools/firebase-mac-catalyst.patch` (firebase-ios-sdk 11.15.0) makes Mac Catalyst keep the login in
UserDefaults instead. Apply it to the resolved package, then build:

    cd <DerivedData>/SourcePackages/checkouts/firebase-ios-sdk
    chmod -R u+w FirebaseAuth && git apply <repo>/tools/firebase-mac-catalyst.patch
    xcodebuild -project BuddyVerse.xcodeproj -scheme BuddyVerse -destination 'platform=macOS,variant=Mac Catalyst' \
      -configuration Release -derivedDataPath <DerivedData> -disableAutomaticPackageResolution \
      CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= CODE_SIGN_ENTITLEMENTS= PROVISIONING_PROFILE_SPECIFIER=

Then put BuddyVerse.app and an Applications symlink in a folder and `hdiutil create -format UDZO`.
Verified: creating an online Tic-Tac-Toe room works from this build.
