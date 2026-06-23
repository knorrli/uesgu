# Changelog

All notable changes to üsgu are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to
follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Production only ever runs a tagged release (see `bin/release` and
`.github/workflows/release.yml`); the version shown in the site footer is the tag
of the running deploy.

## [Unreleased]

## [0.1.0] — 2026-06-23

First tagged release — the "close to v1" baseline. Everything shipped up to this
point: the event feed and filters, accounts and saved filters, web-push
notifications, the venue scrapers, and the public About/Datenschutz pages.

This release also introduces the release engineering itself:

### Added

- Release-only deploys: all services track a `release` branch; pushing a
  `vX.Y.Z` tag fast-forwards it, redeploying web + both crons together on the
  same commit.
- CI on every pull request: Rubocop, Brakeman, and the Minitest + system suites.
- The running version (git tag) is shown in the site footer.
- Dependabot for Bundler and GitHub Actions.

[Unreleased]: https://github.com/knorrli/uesgu/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/knorrli/uesgu/releases/tag/v0.1.0
