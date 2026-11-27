# Deeprowss iOS / TestFlight setup

The iOS target uses the existing Flutter application and the existing app identity:

- Display name: Deeprowss
- Bundle identifier: `com.deeprows.footbolive`
- Devices: iPhone and iPad
- Distribution: TestFlight

## 1. Generate the iOS project

After this workflow is added to the default branch:

1. Open **GitHub → Actions**.
2. Select **Prepare Deeprowss iOS project**.
3. Select **Run workflow** on `main`.
4. Wait for the macOS runner to generate and commit the `ios/` project.
5. Check the simulator-build step. Any plugin that is Android-only or incompatible with the current iOS toolchain must be adapted before TestFlight.

The workflow generates the native Xcode project, Deeprowss launch screen and iOS app icon. It does not change the Android or Windows project folders.

## 2. Firebase notifications

Create an iOS app in the existing Firebase project `deeprows-4d37c` with bundle ID `com.deeprows.footbolive`.

Add this GitHub repository variable:

- `FIREBASE_IOS_APP_ID`: the iOS app ID from Firebase.

Optional GitHub Actions secret:

- `FIREBASE_IOS_API_KEY`: the iOS Firebase API key. If omitted, the existing public project web API key is used.

For actual iOS push delivery, upload an Apple Push Notification authentication key (APNs .p8) in Firebase Console → Project settings → Cloud Messaging. The iOS app's push capability is included in the generated project.

## 3. Apple signing and TestFlight upload

An Apple Developer Program membership and an App Store Connect app record are required. Create the app record using bundle ID `com.deeprows.footbolive`.

Create an **Apple Distribution** certificate exported as a password-protected .p12 file and an **App Store Connect** provisioning profile for this bundle ID. Base64-encode the certificate and profile files before adding them as GitHub Actions secrets.

Add these repository secrets:

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | Apple Developer Team ID |
| `IOS_DISTRIBUTION_CERTIFICATE_BASE64` | Base64-encoded Apple Distribution .p12 |
| `IOS_CERTIFICATE_PASSWORD` | Password used when exporting the .p12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | Base64-encoded App Store provisioning profile |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | Full contents of the App Store Connect .p8 private key |
| `FIREBASE_IOS_API_KEY` | Optional iOS Firebase API key |

Then run **Build and upload Deeprowss to TestFlight** from GitHub Actions. The workflow archives, signs, exports and uploads the IPA. Apple still processes the build before it appears in TestFlight.

Never commit certificates, provisioning profiles, API private keys, or passwords into the repository.
