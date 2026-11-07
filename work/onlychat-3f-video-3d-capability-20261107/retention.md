# Retention receipt — onlychat-3f-video-3d-capability-20261107

- Operation: focused Swift package build/test reused the existing `.build` directory; no versioned app bundle or archive was produced.
- Existing output preserved: `/Users/rogan/appDev/apps/3f-browser-mac/.build` (4.0 GiB). It is the checkout's reusable build directory and contains the test executable used for the successful focused test; no older/replacement version was created by this task.
- Removed outputs: none. No caches, source, worktrees, installed app, or user data were deleted.
- Reference check after the test: no `swift test`, `swift-frontend`, or `swift-build` process remained. An already-running installed `/Users/rogan/Applications/3F Browser.app/Contents/MacOS/ThreeFBrowser` PID 719 was observed and left untouched; it is not an output of this build.
- Capacity after operation: recorded separately by `delivery-proof capacity ... --after`; current Data volume reading at receipt time was approximately 30 GiB free.
