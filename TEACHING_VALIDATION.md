# Validation record — 13 September 2026

## Baseline review

The moved Swift Concurrency project built and ran in Xcode 26.2 on iPhone Air / iOS 26.2. All 98 original simulator tests passed. An independent temporary host package also passed those 98 tests; that temporary harness is not a supported repository command.

Live observations: RocketLaunch.Live returned five launches; Launch Library returned fifty; community SpaceX failed independently. Next, Upcoming, source status and launch details were inspected. Dark themed cards appeared consistent. This was a smoke check, not a full accessibility audit.

An additional isolated diagnostic exposed elapsed launches falling back into Next. The follow-up removes that fallback, shares the Upcoming eligibility policy, and adds two deterministic regressions for initially elapsed data and clock-driven expiry. Provider caches remain available after expiry.

## Follow-up changes

- SpaceX remains enabled intentionally for failure-handling teaching.
- Required-reason UserDefaults manifest is included in the app resources.
- The offline privacy-policy page is linked from About and Settings.
- README paths and test instructions match the nested project; this Day 1 guide and validation record replace missing teaching links.

## Follow-up validation completed

- **100 simulator tests passed**, zero failures, in Xcode 26.2 on iPhone Air / iOS 26.2 at 22:24 local time on 13 September 2026.
- The temporary host harness passed all 100 repository tests plus the original independent diagnostic test (101 total).
- Four older fixture-based tests now inject a fixed clock before their December 2023 launch dates. Their recovery/ordering assertions remain intact; they no longer depend on the incorrect past-launch fallback.
- Both About → Privacy policy and Settings → Privacy policy opened the bundled text successfully in the simulator using the selected dark theme.
- Confirmed PrivacyInfo.xcprivacy and PrivacyPolicy.txt are present in the built app bundle; project and manifest property lists validated.
- README local links resolved and Git whitespace checks passed.

No commit, push, hosted policy publication or App Store submission was performed.

## Remaining acceptance work

- Physical-device notification delivery, permission changes, termination/relaunch and foreground recovery.
- VoiceOver, accessibility Dynamic Type, contrast across themes, small iPhone and iPad layout.
- Instruments profiling before making measured responsiveness claims.
- Release archive/signing/distribution validation.
- A public privacy-policy URL, support and privacy metadata in App Store Connect; confirm external-provider practices and permitted use before release. The bundled policy is accessible offline but does not create a hosted URL.
- Optional scripted UI demo configuration; deterministic test fixtures currently cover failure and timing scenarios.

The project is a teaching build. Passing unit tests does not certify all runtime behaviour or App Store acceptance.
