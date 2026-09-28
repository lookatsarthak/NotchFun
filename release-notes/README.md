# Release notes

One file per release, `<version>.md`, written before running `scripts/release.sh`. The
script refuses to publish without it, and uses the same file twice: rendered into the
update window Sparkle shows inside the app, and as the release notes on GitHub. Write it
for the person reading a small update window, not for the repository.

## Format

```markdown
### New
- **Short bold lead.** One plain sentence on what you get.

### Improved
- **…** …

### Fixed
- **…** …
```

- Use only the sections that apply, in that order. If a release needs something from the
  user (a permission, a setting to check), put a **Heads-up** section first.
- 3–7 bullets in total. One line each: a bold lead, then one sentence.
- Say what the user gets, in their words: "Tab switching is easier to see", not
  "TabSelectionView now uses matchedGeometryEffect".
- Be specific. Never "bug fixes and performance improvements".
- Don't repeat the version or the date; Sparkle and GitHub show both.
- Say plainly when something fixes a security or privacy problem.
- The why and the how belong in commit messages. If a bullet needs a paragraph, it is two
  bullets or a commit message.
