# Next launch screen redesign

Branch: `codex/next-launch-redesign`.

## Scope and behaviour

The Next tab presents a helmet-inspired, live countdown, the provider's scheduled date in local time, and a compact mission/operator/country/rocket card. Mission summaries are optional previews; complete details remain on the existing destination. Settings, About, source status, refresh/retry, watch links when supplied, and the detail screen's reminder controls remain available. Themes remain owned by ThemeManager. No provider, persistence or reminder behaviour was changed.

Exact future times count down; estimated dates never use a sorting date as a fictitious deadline. At or after the scheduled time, the visor says “Awaiting update”, never “Launched”. Existing feature clock updates continue selecting the next eligible launch.

## Ownership

The existing route remains LaunchScheduleView → LaunchScheduleViewModel → AppModel.shared.launchSchedule → provider actors. This narrow visual change preserves the app's existing shared ViewModel/lifecycle arrangement; it is not a whole-app adoption of newer CFA conventions.

LaunchDetails owns countdown eligibility as an immutable domain decision. LaunchScheduleViewModel converts that result into display values. TimelineView supplies presentation ticks while SwiftUI renders the hero; no new network request, actor task, persistent timer or mutable countdown state is introduced. The existing feature actor owns source data and next-launch selection.

At accessibility text sizes, the clock moves below the decorative helmet into a growing card. VoiceOver receives a spoken duration, not a string of colon-separated digits. The artwork is hidden from accessibility.

## Validation — 13 October 2026

- Built and ran the Swift Concurrency RocketLaunch target in Xcode on iPhone Air, iOS 26.2.
- LaunchCountdownTests: 1 passed, 0 failures.
- LaunchScheduleViewModelTests: 17 passed, 0 failures, including three new scenarios for deadline crossing, unknown/replaced times, and absent mission descriptions.
- Visually checked real downloaded USSF-481 data, countdown advancing, System and Nebula themes, settings selection, detail navigation and reminder controls.
- Checked XXX Large and Accessibility 5 Dynamic Type using temporary Xcode overrides, then disabled the override.
- git diff --check passed.
- No physical-device, VoiceOver speech-session or live notification scheduling test was performed.

### Pre-existing baseline failure — unresolved

Before compiling the redesign, the full suite stopped in `LaunchScheduleFeatureTests.testConcurrentInitialLoadsShareOneRequestAndLoadedStateIsRetained`: XCTest reported multiple fulfillment of “Initial request”. The test was stopped; the baseline full suite is not a pass. The focused suites above subsequently passed.

The existing `loadIfNeeded()` captures idle/loading source IDs, then starts child tasks which call unconditional `refresh(source:)`. If a source settles between selection and registration of a joining child task, that child can start another request. Investigate and protect the initial-load condition at actor-isolated request registration in a separate concurrency fix. This redesign does not change that path or claim the whole suite is green.

Command-line xcodebuild could not access CoreSimulator in the sandbox; build/test/run validation used the existing Xcode GUI session instead.

## Artwork provenance

`RocketLaunch/3 - App Resources/Assets.xcassets/LaunchVisor.imageset/launch-visor.png` was created using the built-in image-generation tool from the existing AppIcon. The app icon itself is unchanged. All displayed digits are SwiftUI text.

Prompt: Use case: precise-object-edit. Asset: decorative astronaut helmet visor background for a live iPhone countdown screen. Edit the supplied icon: remove ALL 00:00 digits and their glow entirely, leaving a smooth dark reflective visor so real UI text can be overlaid later. Preserve the elegant silver metal astronaut helmet, blue-purple edge reflections, faint mysterious face, symmetrical front-facing composition and dark background. Keep centre especially dark and quiet for white legible live text. No text, numbers, symbols, logos or watermark anywhere. Square image. Do not draw a UI mockup. This is artwork only.
