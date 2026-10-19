<!-- Security fixes: report privately first (SECURITY.md). -->

**What and why**

**How it was tested** (tests added, platforms built or run)

- [ ] `dart format`, `tool/check_loc.py`, `flutter analyze` and `flutter test --exclude-tags large` pass
- [ ] `node tool/browser_guard_test.js` and `node tool/web_design_test.js` pass (if `assets/web/` changed)
- [ ] English and Korean strings added for new text
- [ ] No new disk writes, no socket outside `NetworkGuard`, protocol bumped for wire changes
- [ ] `CHANGELOG.md` updated if users would notice
