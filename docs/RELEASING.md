# Releasing to TestFlight

Builds are uploaded either from Xcode on the Mac or by the `testflight` workflow. The
workflow archives with automatic, cloud-managed signing through the App Store Connect
API, so no certificates or provisioning profiles are stored in the repository or in
secrets.

## Build numbers

Each upload of a version needs a higher build number than the last one.

- **Xcode:** raise `CURRENT_PROJECT_VERSION` in `project.yml`, run `xcodegen generate`,
  then *Product > Archive* and *Distribute App > App Store Connect*.
- **Workflow:** uses its run number, which starts at 1 and may be lower than a number
  already used from Xcode. Raise `MARKETING_VERSION` first if it is.

## One-time setup

1. **App record.** In [App Store Connect](https://appstoreconnect.apple.com), create
   a new iOS app named **LocSim: Location Simulator** with the bundle ID
   `com.rockykln.locsim`. The home screen keeps the short name *LocSim*. Privacy
   policy, support and beta pages: https://locsim.rockykln.com (source in `site/`). Register the bundle ID
   under *Certificates, Identifiers & Profiles* first if it is not listed.
2. **API key.** Under *Users and Access > Integrations > App Store Connect API*,
   create a team key with the *Admin* role (required for cloud-managed signing).
   Download the `.p8` file; it can only be downloaded once.
3. **Environment.** Under *Settings > Environments*, create `testflight`. Add yourself
   as required reviewer and limit deployment branches and tags to `v*`. Store the
   secrets below in this environment, not as repository secrets, so a run only gets
   them after approval.
4. **Secrets** (in the `testflight` environment):

   | Secret | Value |
   | --- | --- |
   | `ASC_KEY_ID` | Key ID shown next to the key |
   | `ASC_ISSUER_ID` | Issuer ID shown above the key list |
   | `ASC_KEY_P8` | Full contents of the `.p8` file |
   | `TEAM_ID` | 10-character team ID of the paid developer account |

5. **Testers.** Under *TestFlight > Internal Testing*, create a group and add
   team members.
6. **Before going public:** under *Settings > Actions > General*, require approval
   for workflow runs from outside collaborators, and delete old workflow runs.

## Uploading a build

- Run the workflow manually under *Actions > testflight > Run workflow*, or
- push a tag: `git tag v0.1.0 && git push origin v0.1.0`

The build number is the workflow run number and increases with every run. The
version shown to testers is `MARKETING_VERSION` in `project.yml`; raise it for a
new release.

Processing in App Store Connect takes a few minutes after the upload. The build
then appears for the internal group.

## What to Test

The notes for each build live in `docs/testflight/what-to-test.<lang>.txt` (max.
4000 characters). Update them with the release and paste them into *TestFlight >
Build > Test Details* after processing.

## External testers

Access requests arrive at locsim@rockykln.com (see the TestFlight section of the
README). Inviting people outside the team requires external testing:

1. In App Store Connect, create an external group and fill in the beta app
   information (description, feedback email, privacy policy URL).
2. Submit the build for Beta App Review. Once approved, add testers by email.

## Notes

- `ITSAppUsesNonExemptEncryption` is not set: with `true`, uploads fail without a compliance
  code (ITMS-90592), and `false` would be wrong because the idevice library ships its own
  standard encryption (rustls with aws-lc). Answer the encryption questions in App Store
  Connect for each build. Apple asks for documents only for distribution in France, so France
  is excluded from availability until a French declaration is filed.
- If the Developer Disk Image is missing, the app downloads it from a public GitHub
  repository and verifies it by SHA-256. Mention this in the review notes.
- Testers need the same prerequisites as for a source build: Developer Mode,
  LocalDevVPN and their own pairing file.
