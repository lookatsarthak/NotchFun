# boringNotchTests

Unit tests for the clipboard and caffeine logic, using
[swift-testing](https://github.com/swiftlang/swift-testing).

```bash
xcodebuild test -project boringNotch.xcodeproj -scheme boringNotchTests -destination 'platform=macOS'
```

or press ⌘U in Xcode with the `boringNotchTests` scheme selected. They run in about three
seconds and are also run by the `test` job in `.github/workflows/cicd.yml`.

## Why this target does not host the app

This is a **standalone** test bundle: it has no `TEST_HOST`, and instead compiles the
sources under test directly into the bundle.

The usual arrangement — a test bundle hosted by the app, using `@testable import` — would
launch NotchFun to run the tests. On launch the app starts the clipboard monitor, restores
any caffeine session, and reads and writes real user preferences. Running the suite would
therefore poll the developer's actual pasteboard and could take a power assertion on their
machine. It also makes CI flakier, because every test run depends on the whole app
starting cleanly.

Compiling the sources directly avoids all of that. The tests never touch the real
clipboard: they use `NSPasteboard.withUniqueName()`, and every test that writes files gets
its own temporary directory, because swift-testing runs tests in parallel by default.

## The cost: an explicit source list

Because there is no host app, the target has to list the sources it compiles. They are in
the `boringNotchTests` target's Sources build phase in `project.pbxproj`.

**When you add a file you want covered, add it to that build phase too**, otherwise the
tests will not see it. Two constraints on what can go in:

- The file must compile without the `Defaults` package, which the test bundle does not
  link. This is why `ClipboardKeyCaptureService.swift`, `ClipboardPasteService.swift` and
  `Caffeine+Defaults.swift` are excluded.
- Keep it to models and services. View code drags in the rest of the app.

The pure-value-type, injected-protocol shape of these files is what makes this possible:
`CaffeineManager` takes a `PowerAssertionHolding` and a `CaffeineSessionStoring`, so
`FakeAssertion` and `InMemoryCaffeineSessionStore` can stand in for real power assertions
and real storage. Please keep new logic testable the same way.

## What is deliberately not covered

Anything that needs real system state: whether a power assertion actually stops the
display sleeping, whether the CGEvent tap really captures keys, whether auto-paste lands
in the frontmost app. Those were verified by hand against `pmset` and cannot be asserted
in a unit test — see the limitations section in `PowerAssertion.swift`.
