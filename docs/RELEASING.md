# Releasing to TestFlight

Builds are uploaded either from Xcode on the Mac or by the `testflight` workflow. The
workflow archives with automatic, cloud-managed signing through the App Store Connect
API, so no certificates or provisioning profiles are stored in the repository or in
secrets.

## Version and build number

Both come from `project.yml`; the workflow does not override them.

- `MARKETING_VERSION` is the version shown to testers. Raise it for a new release.
- `CURRENT_PROJECT_VERSION` is the build number. App Store Connect rejects an upload
  whose build number is not higher than every earlier upload of the same version, from
  Xcode or from the workflow. Raise it in `project.yml` and commit before every upload.

To upload from Xcode, run `xcodegen generate` after raising the numbers, then
*Product > Archive* and *Distribute App > App Store Connect*.

## One-time setup

1. **App record.** In [App Store Connect](https://appstoreconnect.apple.com), create
   a new iOS app named **LocSim: Location Simulator** with the bundle ID
   `com.rockykln.locsim`. The home screen keeps the short name *LocSim*. Privacy
   policy, support and beta pages: https://locsim.rockykln.com (source in `site/`). Register the bundle IDs
   `com.rockykln.locsim` and `com.rockykln.locsim.tunnel` under *Certificates,
   Identifiers & Profiles* first if they are not listed, both with the *Network
   Extensions* capability, and `com.rockykln.locsim.widgets` (Live Activity) without
   extra capabilities.
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
6. **Repository settings** (set on 4 November 2026): workflow runs from all outside
   contributors need approval (*Settings > Actions > General*), actions must be pinned
   to a full SHA, the `testflight` environment needs approval and allows only `v*` tags,
   and rulesets keep `main` and `v*` tags from being deleted or force-pushed by anyone
   but admins. Secret scanning with push protection and Dependabot alerts are on.

## Uploading a build

1. Raise `CURRENT_PROJECT_VERSION` in `project.yml` (and `MARKETING_VERSION` for a new
   release) and commit.
2. Tag the commit with `v`, `MARKETING_VERSION`, a dash and `CURRENT_PROJECT_VERSION`,
   e.g. for version 1.0 build 4: `git tag v1.0-4 && git push origin v1.0-4`. The
   workflow fails if the tag does not match `project.yml`.
3. Approve the run in the `testflight` environment.

A manual run under *Actions > testflight > Run workflow* must select the tag (e.g.
`v1.0-4`) under *Use workflow from*, not a branch: the environment only allows `v*` tags,
and the tag check fails for any other ref.

Processing in App Store Connect takes a few minutes after the upload. The build
then appears for the internal group.

## What to Test

The notes for each build live in `docs/testflight/what-to-test.<lang>.txt` (max.
4000 characters). Update them with the release and paste them into *TestFlight >
Build > Test Details* after processing.

## External testers

Access requests for Early Access and development builds arrive at locsim@rockykln.com
(the website's beta dialog, locsim.rockykln.com/#beta, prepares the email). Inviting people outside the team requires external testing:

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
- Testers need the same prerequisites as for a source build: Developer Mode and their
  own pairing file.
- The packet tunnel makes App Review treat LocSim as a possible VPN app (guideline 5.4,
  organization accounts only). The review notes must explain that it only reaches the
  device itself, and China should stay excluded from availability.

## Setup guide

The setup guide links the scripts at a fixed commit, not at `main`, so a later change
cannot reach users before it is part of a build. After uploading a build, point the
links at the commit the build was made from and commit the pages:

    tools/pin-setup.sh <commit>
