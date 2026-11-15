import Foundation
import XCTest
import WebKit
@testable import ThreeFBrowser

final class ThreeFBrowserControlTests: XCTestCase {
    @MainActor
    func testControlDescriptorIsSharedOnlyForTheProductionBundle() throws {
        let support = URL(fileURLWithPath: "/tmp/threef-control-descriptor-test", isDirectory: true)
        let shared = support.appendingPathComponent("3F Browser/only-chat-control.json")
        let production = ThreeFBrowserControlServer.descriptorURL(
            applicationSupportDirectory: support,
            bundleIdentifier: "com.rogan.threef.browser"
        )
        let candidate = ThreeFBrowserControlServer.descriptorURL(
            applicationSupportDirectory: support,
            bundleIdentifier: "com.rogan.threef.browser.cef-dev"
        )
        let explicit = URL(fileURLWithPath: "/tmp/custom-control/descriptor.json")
        let overridden = ThreeFBrowserControlServer.descriptorURL(
            applicationSupportDirectory: support,
            bundleIdentifier: "com.rogan.threef.browser.cef-dev",
            override: explicit
        )
        let aiProfile = URL(fileURLWithPath: "/tmp/spaceo-agent-profile-3f-test", isDirectory: true)
        let aiDescriptor = ThreeFBrowserControlServer.descriptorURL(
            applicationSupportDirectory: support,
            bundleIdentifier: "com.rogan.threef.browser",
            sessionDirectory: aiProfile
        )

        XCTAssertEqual(production, shared)
        XCTAssertNotEqual(candidate, shared)
        XCTAssertTrue(candidate.path.contains("QA Profiles/com.rogan.threef.browser.cef-dev"))
        XCTAssertEqual(overridden, explicit)
        XCTAssertEqual(aiDescriptor, aiProfile.appendingPathComponent("only-chat-control.json"))
    }

    @MainActor
    func testControlDescriptorCanUseExplicitQAPathWithoutSharingProductionDescriptor() {
        let support = URL(fileURLWithPath: "/tmp/threef-control-descriptor-test", isDirectory: true)
        let production = ThreeFBrowserControlServer.descriptorURL(applicationSupportDirectory: support, bundleIdentifier: "com.rogan.threef.browser")
        let qa = URL(fileURLWithPath: "/tmp/onlychat-3f-qa-target.json")
        XCTAssertNotEqual(qa, production)
        XCTAssertEqual(ThreeFBrowserControlServer.descriptorURL(applicationSupportDirectory: support, bundleIdentifier: "com.rogan.threef.browser.qa.snooze20261108", override: qa), qa)
    }

    func testControlPageStateTracksTheSelectedTabAndRejectsStaleWebViewURL() throws {
        let selectedPage = try XCTUnwrap(URL(string: "https://example.com/"))
        let stalePage = try XCTUnwrap(URL(string: "https://youtube.com/"))

        XCTAssertTrue(ThreeFBrowserControlPageState.isReady(modelURL: selectedPage, webViewURL: selectedPage))
        XCTAssertFalse(ThreeFBrowserControlPageState.isReady(modelURL: nil, webViewURL: stalePage),
                       "a selected new tab must not expose the previous tab's WebView URL")
        XCTAssertFalse(ThreeFBrowserControlPageState.isReady(modelURL: selectedPage, webViewURL: stalePage),
                       "a page must not be read while WebKit still shows the previous page")
    }

    func testFocusFenceContactRequiresAValidRulesPayload() {
        XCTAssertFalse(ThreeFBrowserControlController.usableFocusFenceRules(
            Data(#"{"todaySeconds":0,"dailyCapMinutes":180,"blocked":false,"browserSeconds":{}}"#.utf8)
        ), "a usage summary is not a navigation rules payload")
        XCTAssertTrue(ThreeFBrowserControlController.usableFocusFenceRules(
            Data(#"{"blockedDomains":[],"blockedUrlParts":[],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        ))
        XCTAssertFalse(ThreeFBrowserControlController.usableFocusFenceRules(
            Data(#"{"blockedDomains":[],"blockedUrlParts":[]}"#.utf8)
        ))
        XCTAssertFalse(ThreeFBrowserControlController.usableFocusFenceRules(
            Data(#"{"blockedDomains":[],"blockedUrlParts":[],"keywords":null}"#.utf8)
        ))
        XCTAssertFalse(ThreeFBrowserControlController.usableFocusFenceRules(
            Data(#"{"blockedDomains":[],"blockedUrlParts":[],"keywords":[],"blockExceptions":null}"#.utf8)
        ))
        XCTAssertFalse(ThreeFBrowserControlController.usableFocusFenceRules(
            Data(#"{"blockedDomains":[],"blockedUrlParts":[],"keywords":[]}"#.utf8)
        ))
        XCTAssertFalse(ThreeFBrowserControlController.usableFocusFenceRules(
            Data(#"{"blockedDomains":[]}"#.utf8)
        ))
        XCTAssertFalse(ThreeFBrowserControlController.usableFocusFenceRules(Data("not-json".utf8)))
    }

    func testFocusFenceRulesCacheKeepsLatestValidRulesAndRejectsCorruption() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("3f-rules-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FocusFenceRulesCache(directory: directory)
        let first = Data(#"{"blockedDomains":["juso3.net"],"blockedUrlParts":[],"adultProtectedDomains":["juso3.net"],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let latest = Data(#"{"blockedDomains":["juso3.net","new-adult.example"],"blockedUrlParts":[],"adultProtectedDomains":["juso3.net","new-adult.example"],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)

        XCTAssertNil(cache.load(), "no previous successful sync must not invent an allow policy")
        XCTAssertTrue(cache.save(first))
        XCTAssertTrue(cache.save(latest))
        XCTAssertEqual(cache.load(), latest)
        XCTAssertFalse(cache.save(Data("{}".utf8)), "invalid response must not replace the last valid local rules")
        XCTAssertEqual(cache.load(), latest)

        try Data("corrupt".utf8).write(to: cache.rulesURL, options: .atomic)
        XCTAssertNil(cache.load(), "corrupt storage must not be treated as an allow-all policy")
    }

    func testFocusFenceRulesCacheMigratesCompleteLegacySnapshotWithoutOverwritingIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("3f-rules-cache-legacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FocusFenceRulesCache(directory: directory)
        let legacy = Data(#"{"blockedDomains":["blocked.example"],"blockedUrlParts":["/limit"],"keywords":["hidden"],"blockExceptions":["allowed.example"]}"#.utf8)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try legacy.write(to: cache.rulesURL, options: .atomic)

        let loaded = try XCTUnwrap(cache.load())
        let rules = try XCTUnwrap(JSONSerialization.jsonObject(with: loaded) as? [String: Any])
        XCTAssertEqual(rules["blockedDomains"] as? [String], ["blocked.example"])
        XCTAssertEqual(rules["blockExceptions"] as? [String], ["allowed.example"])
        XCTAssertEqual(rules["adultProtectedDomains"] as? [String], [])
        XCTAssertEqual(rules["adultProtectedUrlParts"] as? [String], [])
        XCTAssertEqual(rules["adultProtectedKeywords"] as? [String], [])
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(
            URL(string: "https://blocked.example/path")!, rules: loaded
        ), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(
            URL(string: "https://allowed.example/path")!, rules: loaded
        ), true)
        XCTAssertFalse(cache.save(legacy), "new network writes must still require the current policy schema")
        XCTAssertEqual(try Data(contentsOf: cache.rulesURL), legacy,
                       "reading a legacy cache must not rewrite the durable last-known snapshot")
    }

    @MainActor
    func testFocusFenceRulesAllowUnlistedHostAndBlockDomainAndURLPart() throws {
        let rules = Data(#"{"blockedDomains":["www.blocked.example"],"blockedUrlParts":["disallowed-path"],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":["hiddenword"],"blockExceptions":[]}"#.utf8)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://developer.apple.com")!, rules: rules), true)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://sub.blocked.example/page")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://example.com/disallowed-path")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://example.com/search?q=hiddenword")!, rules: rules), false)
    }

    @MainActor
    func testFocusFenceAdultDirectoryHostsBlockAllPathsAndSubdomains() throws {
        let rules = Data(#"{"blockedDomains":["juso3.net","yako1234.com","mingky26.com"],"blockedUrlParts":[],"adultProtectedDomains":["juso3.net","yako1234.com","mingky26.com"],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        for value in [
            "https://juso3.net/category/adult",
            "https://www.juso3.net/category/adult",
            "https://video.yako1234.com/watch/1",
            "https://mingky26.com/",
        ] {
            XCTAssertEqual(
                ThreeFBrowserControlController.focusFenceAllows(URL(string: value)!, rules: rules),
                false,
                value
            )
        }
        XCTAssertEqual(
            ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://notjuso3.net/category/adult")!, rules: rules),
            true,
            "domain matching must use DNS-label boundaries"
        )
    }

    @MainActor
    func testFocusFenceBlocksRotatingYadongURLsFromURLContainsStem() throws {
        let rules = Data(#"{"blockedDomains":[],"blockedUrlParts":["yadong"],"adultProtectedDomains":[],"adultProtectedUrlParts":["yadong"],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":["yadongkorea17.com"]}"#.utf8)
        for value in [
            "https://yadongkorea17.com/",
            "https://yadongkorea17.com",
            "https://yadongkorea17.com?category=adult",
            "https://m.yadongkorea123456.co.kr/category/adult",
            "https://yadongtv99999.example/path",
            "https://www.google.com/search?q=yadongkorea17",
        ] {
            XCTAssertEqual(
                ThreeFBrowserControlController.focusFenceAllows(URL(string: value)!, rules: rules),
                false,
                value
            )
        }
        XCTAssertEqual(
            ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://safe.example/page")!, rules: rules),
            true
        )
    }

    func testFocusFenceRulesNormalizeWWWAndBlockProxyDestination() throws {
        let pathRules = Data(#"{"blockedDomains":[],"blockedUrlParts":["blocked.example/disallowed"],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://www.blocked.example/disallowed")!, rules: pathRules), false)

        let proxyRules = Data(#"{"blockedDomains":["blocked.example"],"blockedUrlParts":[],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://proxy.example/?target=https%3A%2F%2Fblocked.example%2Fpage")!, rules: proxyRules), false)
    }

    func testFocusFenceExceptionAndUnavailableRulesAreHandled() throws {
        let rules = Data(#"{"blockedDomains":["blocked.example"],"blockedUrlParts":["forbidden"],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":["hiddenword"],"blockExceptions":["example.com"]}"#.utf8)
        XCTAssertEqual(ThreeFControlControllerTestShim.evaluate("https://blocked.example", rules: rules), false)
        XCTAssertEqual(ThreeFControlControllerTestShim.evaluate("https://sub.example.com/forbidden?q=hiddenword", rules: rules), true)
        XCTAssertNil(ThreeFControlControllerTestShim.evaluate("https://developer.apple.com", rules: Data("{}".utf8)))
        XCTAssertNil(ThreeFControlControllerTestShim.evaluate(
            "https://developer.apple.com",
            rules: Data(#"{"blockedDomains":[],"blockedUrlParts":[],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[]}"#.utf8)
        ), "a policy missing its exception list is malformed and must fail closed")
    }

    @MainActor
    func testAdultProtectionOverridesExceptionsButOrdinaryExceptionsStillWork() throws {
        let rules = Data(#"{"blockedDomains":["adult.example","ordinary.example"],"blockedUrlParts":["yadongkorea"],"adultProtectedDomains":["adult.example"],"adultProtectedUrlParts":["yadongkorea"],"adultProtectedKeywords":["adult-term"],"keywords":["adult-term"],"blockExceptions":["adult.example","ordinary.example","yadongkorea17.com"]}"#.utf8)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://adult.example/allowed")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://sub.adult.example/")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://safe.example/search?q=yadongkorea17")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://yadongkorea17.com/")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://proxy.example/?target=https%3A%2F%2Fadult.example%2Fwatch")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://safe.example/search?q=adult-term")!, rules: rules), false)
        XCTAssertEqual(ThreeFBrowserControlController.focusFenceAllows(URL(string: "https://ordinary.example/")!, rules: rules), true)
    }

    func testWebKitNavigationRequiresFocusFenceApprovalIncludingDownloads() {
        XCTAssertEqual(BrowserWebView.Coordinator.navigationDecision(isAllowed: true, shouldDownload: false, allowsDownloads: true), .allow)
        XCTAssertEqual(BrowserWebView.Coordinator.navigationDecision(isAllowed: false, shouldDownload: false, allowsDownloads: true), .cancel)
        XCTAssertEqual(BrowserWebView.Coordinator.navigationDecision(isAllowed: nil, shouldDownload: false, allowsDownloads: true), .cancel)
        XCTAssertEqual(BrowserWebView.Coordinator.navigationDecision(isAllowed: true, shouldDownload: true, allowsDownloads: true), .download)
        XCTAssertEqual(BrowserWebView.Coordinator.navigationDecision(isAllowed: false, shouldDownload: true, allowsDownloads: true), .cancel)
        XCTAssertEqual(BrowserWebView.Coordinator.navigationDecision(isAllowed: true, shouldDownload: true, allowsDownloads: false), .cancel)
    }

    @MainActor
    func testPolicyStatusReportsAllowedWithoutLeakingSensitiveURL() async throws {
        let secretURL = try XCTUnwrap(URL(string: "https://example.com/private/path?query=secret"))
        let rules = Data(#"{"blockedDomains":[],"blockedUrlParts":[],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let controller = ThreeFBrowserControlController(policyRulesFetcher: { rules })
        let model = BrowserModel()
        model.currentURL = secretURL
        let surface = TestThreeFBrowserControlSurface(url: secretURL)
        controller.attach(model: model, surface: surface)

        let (status, payload) = await controller.handle(ThreeFControlRequest(method: "GET", path: "/v1/policy/status", headers: [:], body: Data()))

        XCTAssertEqual(status, 200)
        XCTAssertEqual(payload["decision"] as? String, "allowed")
        XCTAssertEqual(payload["fetchStatus"] as? String, "success")
        XCTAssertEqual(payload["schemaValid"] as? Bool, true)
        let serialized = String(describing: payload)
        XCTAssertFalse(serialized.contains("example.com"))
        XCTAssertFalse(serialized.contains("private"))
        XCTAssertFalse(serialized.contains("secret"))
    }

    @MainActor
    func testPolicyStatusReportsBlockedAndFetchOrSchemaFailureAsUnknown() async throws {
        let url = try XCTUnwrap(URL(string: "https://blocked.example/private?q=needle"))
        let blockedRules = Data(#"{"blockedDomains":["blocked.example"],"blockedUrlParts":[],"adultProtectedDomains":[],"adultProtectedUrlParts":[],"adultProtectedKeywords":[],"keywords":[],"blockExceptions":[]}"#.utf8)
        let blockedController = ThreeFBrowserControlController(policyRulesFetcher: { blockedRules })
        let blockedModel = BrowserModel()
        blockedModel.currentURL = url
        let blockedSurface = TestThreeFBrowserControlSurface(url: url)
        blockedController.attach(model: blockedModel, surface: blockedSurface)
        let request = ThreeFControlRequest(method: "GET", path: "/v1/policy/status", headers: [:], body: Data())
        let (blockedStatus, blockedPayload) = await blockedController.handle(request)
        XCTAssertEqual(blockedStatus, 200)
        XCTAssertEqual(blockedPayload["decision"] as? String, "blocked")
        XCTAssertEqual(blockedPayload["reasonCode"] as? String, "rules_block")

        for fetcher in [({ nil as Data? }), ({ Data("{}".utf8) as Data? })] {
            let controller = ThreeFBrowserControlController(policyRulesFetcher: fetcher)
            let model = BrowserModel()
            controller.attach(model: model, surface: TestThreeFBrowserControlSurface(url: url))
            let (status, payload) = await controller.handle(request)
            XCTAssertEqual(status, 200)
            XCTAssertEqual(payload["decision"] as? String, "unknown")
            XCTAssertFalse((String(describing: payload)).contains("blocked.example"))
            XCTAssertFalse((String(describing: payload)).contains("needle"))
        }
    }

    @MainActor
    func testControlNavigationFailsClosedWithoutFocusFencePolicy() async throws {
        let controller = ThreeFBrowserControlController(navigationAuthorizer: { _ in nil })
        let request = try navigationRequest("https://developer.apple.com/documentation")

        let (status, payload) = await controller.handle(request)

        XCTAssertEqual(status, 503)
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["error"] as? String, "Focus Fence navigation policy is unavailable")
    }

    @MainActor
    func testControlNavigationStopsWhenFocusFenceDeniesURL() async throws {
        var checkedHost: String?
        let controller = ThreeFBrowserControlController(navigationAuthorizer: { url in
            checkedHost = url.host
            return false
        })
        let request = try navigationRequest("https://developer.apple.com/documentation")

        let (status, payload) = await controller.handle(request)

        XCTAssertEqual(checkedHost, "developer.apple.com")
        XCTAssertEqual(status, 403)
        XCTAssertEqual(payload["ok"] as? Bool, false)
        XCTAssertEqual(payload["error"] as? String, "navigation blocked by Focus Fence")
    }

    @MainActor
    func testControlNavigationDoesNotClaimSuccessWhenBrowserViewIsNotReady() async throws {
        var presentationRequests = 0
        let controller = ThreeFBrowserControlController(navigationAuthorizer: { _ in true })
        controller.setBrowserWindowPresenter {
            presentationRequests += 1
            return false
        }

        let (status, payload) = await controller.handle(try navigationRequest("https://example.com/"))

        XCTAssertEqual(presentationRequests, 0)
        XCTAssertEqual(status, 503)
        XCTAssertEqual(payload["error"] as? String, "browser view not ready")
    }

    @MainActor
    func testControlNavigationPresentsStandaloneWindowBeforeNavigating() async throws {
        let destination = try XCTUnwrap(URL(string: "https://example.com/"))
        let controller = ThreeFBrowserControlController(navigationAuthorizer: { _ in true })
        let model = BrowserModel()
        let surface = TestThreeFBrowserControlSurface(url: destination)
        var presentationRequests = 0
        controller.attach(model: model, surface: surface)
        controller.setBrowserWindowPresenter {
            presentationRequests += 1
            return true
        }

        let request = try navigationRequest(destination.absoluteString)
        let navigation = Task { @MainActor in await controller.handle(request) }
        try await Task.sleep(nanoseconds: 5_000_000)
        controller.navigationDidFinish(for: surface)
        let (status, payload) = await navigation.value

        XCTAssertEqual(presentationRequests, 1)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(payload["url"] as? String, destination.absoluteString)
    }

    @MainActor
    func testNavigationWaitsForWebViewCompletionAndPropagatesFailure() async throws {
        let controller = ThreeFBrowserControlController(navigationAuthorizer: { _ in true })
        var started = false
        let target = NSObject()
        let pending = Task { @MainActor in
            await controller.performNavigation(for: target) { started = true }
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        XCTAssertTrue(started)
        XCTAssertFalse(pending.isCancelled)
        controller.navigationDidFinish(for: target)
        let completed = await pending.value
        XCTAssertTrue(completed)

        let failed = Task { @MainActor in
            await controller.performNavigation(for: target) {}
        }
        try await Task.sleep(nanoseconds: 5_000_000)
        controller.navigationDidFail(for: target)
        let failedResult = await failed.value
        XCTAssertFalse(failedResult)
    }

    @MainActor
    func testNavigationIgnoresCompletionFromAnotherWindow() async throws {
        let controller = ThreeFBrowserControlController(navigationAuthorizer: { _ in true })
        let target = NSObject()
        let otherWindow = NSObject()
        let pending = Task { @MainActor in
            await controller.performNavigation(for: target) {}
        }

        try await Task.sleep(nanoseconds: 5_000_000)
        controller.navigationDidFinish(for: otherWindow)
        let secondNavigation = await controller.performNavigation(for: otherWindow) {}
        XCTAssertFalse(secondNavigation)
        controller.navigationDidFinish(for: target)
        let result = await pending.value
        XCTAssertTrue(result)
    }

    func testHTTPParserHandlesFragmentedBodyAndNormalizesHeaders() {
        let first = Data("POST /v1/navigate HTTP/1.1\r\nHost: 127.0.0.1:43210\r\nContent-Length: 29\r\nAuthorization: Bearer sample\r\n\r\n{\"url\":\"https://".utf8)
        if case .incomplete = ThreeFControlRequestParser.parse(first) {} else { XCTFail("partial request must wait for remaining body") }

        var complete = first
        complete.append(Data("example.com\"}".utf8))
        guard case .request(let request) = ThreeFControlRequestParser.parse(complete) else {
            return XCTFail("complete request should parse")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/navigate")
        XCTAssertEqual(request.headers["host"], "127.0.0.1:43210")
        XCTAssertEqual(request.headers["authorization"], "Bearer sample")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), "{\"url\":\"https://example.com\"}")
    }

    func testHTTPParserRejectsOversizedBodiesDuplicateHeadersAndTransferEncoding() {
        let oversized = Data("POST /v1/act HTTP/1.1\r\nHost: 127.0.0.1:1\r\nContent-Length: 16385\r\n\r\n".utf8)
        guard case .invalid(413, _) = ThreeFControlRequestParser.parse(oversized) else { return XCTFail("oversized body must reject") }

        let duplicate = Data("GET /v1/status HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n".utf8)
        guard case .invalid(400, _) = ThreeFControlRequestParser.parse(duplicate) else { return XCTFail("duplicate headers must reject") }

        let chunked = Data("POST /v1/act HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)
        guard case .invalid(400, _) = ThreeFControlRequestParser.parse(chunked) else { return XCTFail("chunked request must reject") }
    }

    @MainActor
    func testLoopbackControlServerRequiresTokenAndRemovesTemporaryDescriptor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("threef-control-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptorURL = root.appendingPathComponent("only-chat-control.json")
        let server = ThreeFBrowserControlServer(descriptorURL: descriptorURL)
        server.start()
        defer { server.stop() }

        var descriptor: [String: Any]?
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: descriptorURL),
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                descriptor = value
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let value = try XCTUnwrap(descriptor)
        XCTAssertEqual(value["host"] as? String, "127.0.0.1")
        let port = try XCTUnwrap(value["port"] as? Int)
        let token = try XCTUnwrap(value["token"] as? String)
        XCTAssertEqual(token.count, 96)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: descriptorURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let endpoint = URL(string: "http://127.0.0.1:\(port)/v1/status")!
        var unauthorizedRequest = URLRequest(url: endpoint)
        unauthorizedRequest.timeoutInterval = 2
        let (unauthorizedData, unauthorizedResponse) = try await URLSession.shared.data(for: unauthorizedRequest)
        XCTAssertEqual((unauthorizedResponse as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: unauthorizedData) as? [String: Any])?["error"] as? String, "unauthorized")

        var authorizedRequest = URLRequest(url: endpoint)
        authorizedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        authorizedRequest.timeoutInterval = 2
        let (_, authorizedResponse) = try await URLSession.shared.data(for: authorizedRequest)
        XCTAssertEqual((authorizedResponse as? HTTPURLResponse)?.statusCode, 503, "the authenticated API reaches the controller, which has no WKWebView in this test")

        server.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptorURL.path))
    }

    @MainActor
    func testStoppingOlderControlServerPreservesTheNewerServersDescriptor() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("threef-control-owner-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptorURL = root.appendingPathComponent("only-chat-control.json")
        let older = ThreeFBrowserControlServer(descriptorURL: descriptorURL)
        let newer = ThreeFBrowserControlServer(descriptorURL: descriptorURL)
        defer { older.stop(); newer.stop() }

        older.start()
        let oldToken = try await waitForDescriptorToken(at: descriptorURL)
        newer.start()
        let newToken = try await waitForDescriptorToken(at: descriptorURL, differentFrom: oldToken)
        XCTAssertNotEqual(oldToken, newToken)

        older.stop()
        let survivingToken = try await waitForDescriptorToken(at: descriptorURL)
        XCTAssertEqual(survivingToken, newToken)

        newer.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: descriptorURL.path))
    }

    @MainActor
    func testActiveServerReclaimsDescriptorLeftByTerminatedInstance() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("threef-control-reclaim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let descriptorURL = root.appendingPathComponent("only-chat-control.json")
        let server = ThreeFBrowserControlServer(descriptorURL: descriptorURL)
        server.start()
        defer { server.stop() }

        _ = try await waitForDescriptorToken(at: descriptorURL)
        let liveDescriptor = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: descriptorURL)) as? [String: Any]
        )
        let livePort = try XCTUnwrap(liveDescriptor["port"] as? Int)
        let staleDescriptor: [String: Any] = [
            "schemaVersion": 1,
            "host": "127.0.0.1",
            "port": 1,
            "token": String(repeating: "x", count: 96)
        ]
        try JSONSerialization.data(withJSONObject: staleDescriptor).write(to: descriptorURL, options: .atomic)

        server.publishForActiveInstance()

        let repairedDescriptor = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: descriptorURL)) as? [String: Any]
        )
        XCTAssertEqual(repairedDescriptor["port"] as? Int, livePort)
        XCTAssertNotEqual(repairedDescriptor["token"] as? String, staleDescriptor["token"] as? String)
    }

    @MainActor
    private func waitForDescriptorToken(at url: URL, differentFrom priorToken: String? = nil) async throws -> String {
        for _ in 0..<50 {
            if let data = try? Data(contentsOf: url),
               let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let token = value["token"] as? String,
               token != priorToken {
                return token
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw URLError(.timedOut)
    }

    private func navigationRequest(_ url: String) throws -> ThreeFControlRequest {
        let body = try JSONSerialization.data(withJSONObject: ["url": url])
        return ThreeFControlRequest(method: "POST", path: "/v1/navigate", headers: [:], body: body)
    }
}

@MainActor
private final class TestThreeFBrowserControlSurface: ThreeFBrowserControlSurface {
    var url: URL?
    var title: String? = "Example"
    var backURL: URL?
    var forwardURL: URL?

    init(url: URL?) { self.url = url }

    func goBackInBrowser() {}
    func goForwardInBrowser() {}
    func reloadBrowserPage() {}
    func evaluateBrowserJavaScript(_ script: String) async throws -> Any? { "" }
}

private enum ThreeFControlControllerTestShim {
    static func evaluate(_ value: String, rules: Data) -> Bool? {
        ThreeFBrowserControlController.focusFenceAllows(URL(string: value)!, rules: rules)
    }
}
