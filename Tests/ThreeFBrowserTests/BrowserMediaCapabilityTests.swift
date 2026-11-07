import AppKit
import XCTest
import WebKit

@MainActor
final class BrowserMediaCapabilityTests: XCTestCase {
    private final class NavigationWaiter: NSObject, WKNavigationDelegate {
        private var continuation: CheckedContinuation<Void, Error>?

        func wait(for webView: WKWebView, loading html: String, baseURL: URL) async throws {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                webView.navigationDelegate = self
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            continuation?.resume()
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private func loadLocalHTML(_ html: String, in webView: WKWebView) async throws -> NavigationWaiter {
        let waiter = NavigationWaiter()
        try await waiter.wait(
            for: webView,
            loading: html,
            baseURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
        return waiter
    }

    private func attachedWebView() -> (WKWebView, NSWindow) {
        let webView = WKWebView(frame: .zero)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        return (webView, window)
    }

    func testHTML5VideoDecodedPlaybackAdvancesFromLocalFixture() async throws {
        let (webView, window) = attachedWebView()
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            window.orderOut(nil)
        }
        window.makeKeyAndOrderFront(nil)
        await Task.yield()
        let html = """
        <!doctype html><meta charset="utf-8">
        <video id="fixture" preload="auto" muted playsinline>
          <source src="data:video/mp4;base64,AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAANcbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAAlgAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAod0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAlgAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAABAAAAAQAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAJYAAAQAAABAAAAAAH/bWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAoAAAAGABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABqm1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAWpzdGJsAAAAvnN0c2QAAAAAAAAAAQAAAK5hdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAABAAEABIAAAASAAAAAAAAAABFExhdmM2My4xLjEwMSBsaWJ4MjY0AAAAAAAAAAAAAAAAGP//AAAANGF2Y0MBZAAK/+EAF2dkAAqs2V7ARAAAAwAEAAADACg8SJZYAQAGaOvjyyLA/fj4AAAAABBwYXNwAAAAAQAAAAEAAAAUYnRydAAAAAAAACZwAAAAAAAAABhzdHRzAAAAAAAAAAEAAAADAAAIAAAAABRzdHNzAAAAAAAAAAEAAAABAAAAKGN0dHMAAAAAAAAAAwAAAAEAABAAAAAAAQAAGAAAAAABAAAIAAAAABxzdHNjAAAAAAAAAAEAAAABAAAAAwAAAAEAAAAgc3RzegAAAAAAAAAAAAAAAwAAAsoAAAAMAAAADAAAABRzdGNvAAAAAAAAAAEAAAOMAAAAYXVkdGEAAABZbWV0YQAAAAAAAAAhaGRscgAAAAAAAAAAbWRpcmFwcGwAAAAAAAAAAAAAAAAsaWxzdAAAACSpdG9vAAAAHGRhdGEAAAABAAAAAExhdmY2My4xLjEwMQAAAAhmcmVlAAAC6m1kYXQAAAKtBgX//6ncRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9MSByZWY9MyBkZWJsb2NrPTE6MDowIGFuYWx5c2U9MHgzOjB4MTEzIG1lPWhleCBzdWJtZT03IHBzeT0xIHBzeV9yZD0xLjAwOjAuMDAgbWl4ZWRfcmVmPTEgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0xIDh4OGRjdD0xIGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0PS0yIHRocmVhZHM9MSBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTMgYl9weXJhbWlkPTIgYl9hZGFwdD0xIGJfYmlhcz0wIGRpcmVjdD0xIHdlaWdodGI9MSBvcGVuX2dvcD0wIHdlaWdodHA9MiBrZXlpbnQ9MjUwIGtleWludF9taW49NSBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAgcmNfbG9va2FoZWFkPTQwIHJjPWNyZiBtYnRyZWU9MSBjcmY9MjMuMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89MS40MCBhcT0xOjEuMDAAgAAAABVliIQAEf/+5+P8Cmm1qxOLjVAKurEAAAAIQZoibEP//uAAAAAIAZ5BeQ//s4E=" type="video/mp4">
        </video>
        """
        let navigationWaiter = try await loadLocalHTML(html, in: webView)
        withExtendedLifetime(navigationWaiter) {}

        let callbackAvailability = try await webView.evaluateJavaScript("""
          (() => { const v = document.getElementById('fixture');
            return typeof v.requestVideoFrameCallback === 'function'; })()
          """) as? Bool ?? false
        let deadline = Date().addingTimeInterval(8)
        var state = ""
        var ready = false
        repeat {
            state = try await webView.evaluateJavaScript("""
              (() => { const v = document.getElementById('fixture');
                if (v.paused && v.readyState >= 2) v.play().catch(() => {});
                return JSON.stringify({ readyState: v.readyState, duration: v.duration,
                  width: v.videoWidth, height: v.videoHeight, currentTime: v.currentTime,
                  paused: v.paused, decoded: v.getVideoPlaybackQuality
                    ? v.getVideoPlaybackQuality().totalVideoFrames : null,
                  presented: window.__presentedVideoFrames || 0,
                  canPlay: v.canPlayType('video/mp4') }); })()
              """) as? String ?? ""
            let parsed = try XCTUnwrap(state.data(using: .utf8))
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: parsed) as? [String: Any])
            if let rs = values["readyState"] as? Int, rs >= 2,
               let duration = values["duration"] as? Double, duration.isFinite, duration > 0,
               let width = values["width"] as? Int, width > 0,
               let height = values["height"] as? Int, height > 0,
               values["canPlay"] is String { ready = true; break }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTAssertTrue(ready, "Local video fixture did not become playable; last state: \(state)")
        if callbackAvailability {
            _ = try await webView.evaluateJavaScript("""
              (() => { const v = document.getElementById('fixture');
                window.__presentedVideoFrames = 0;
                const count = () => { window.__presentedVideoFrames++;
                  v.requestVideoFrameCallback(count); };
                v.requestVideoFrameCallback(count); return true; })()
              """)
        }
        let startData = try XCTUnwrap(state.data(using: .utf8))
        let start = try XCTUnwrap(JSONSerialization.jsonObject(with: startData) as? [String: Any])
        let startTime = try XCTUnwrap(start["currentTime"] as? Double)
        let startFrames = start["decoded"] as? Int ?? 0
        try await Task.sleep(for: .milliseconds(700))
        let rawEndState = try await webView.evaluateJavaScript("""
          (() => { const v = document.getElementById('fixture'); return JSON.stringify({
            currentTime: v.currentTime, decoded: v.getVideoPlaybackQuality
              ? v.getVideoPlaybackQuality().totalVideoFrames : null,
            presented: window.__presentedVideoFrames || 0 }); })()
          """)
        let endState = try XCTUnwrap(rawEndState as? String)
        let endData = try XCTUnwrap(endState.data(using: .utf8))
        let end = try XCTUnwrap(JSONSerialization.jsonObject(with: endData) as? [String: Any])
        let endTime = try XCTUnwrap(end["currentTime"] as? Double)
        XCTAssertGreaterThan(endTime - startTime, 0.15, "Video playback did not advance: \(endState)")
        if callbackAvailability {
            let presentedFrames = try XCTUnwrap(end["presented"] as? Int)
            XCTAssertGreaterThan(presentedFrames, 0, "requestVideoFrameCallback reported no presented frames")
        } else if let endFrames = end["decoded"] as? Int {
            XCTAssertGreaterThan(endFrames, startFrames, "getVideoPlaybackQuality is unavailable for presented-frame observation; decoded frame count did not increase")
        } else {
            XCTFail("Neither requestVideoFrameCallback nor getVideoPlaybackQuality is available to observe presented frames")
        }
    }

    func testWebGLRendersTriangleFromLocalFixture() async throws {
        let (webView, window) = attachedWebView()
        defer {
            webView.stopLoading()
            webView.navigationDelegate = nil
            window.orderOut(nil)
        }
        let navigationWaiter = try await loadLocalHTML(
            "<!doctype html><canvas id=\"fixture\"></canvas>", in: webView
        )
        withExtendedLifetime(navigationWaiter) {}
        let deadline = Date().addingTimeInterval(8)
        var result: Any?
        repeat {
            result = try await webView.evaluateJavaScript("""
              (() => { const c = document.getElementById('fixture');
                c.width = 16; c.height = 16;
                const gl = c.getContext('webgl') || c.getContext('experimental-webgl');
                if (!gl) return JSON.stringify({ ok: false });
                gl.viewport(0, 0, 16, 16);
                gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT);
                const vs = gl.createShader(gl.VERTEX_SHADER);
                gl.shaderSource(vs, 'attribute vec2 p; void main(){gl_Position=vec4(p,0.0,1.0);}');
                gl.compileShader(vs);
                const fs = gl.createShader(gl.FRAGMENT_SHADER);
                gl.shaderSource(fs, 'precision mediump float; void main(){gl_FragColor=vec4(1.0,0.0,0.0,1.0);}');
                gl.compileShader(fs);
                const program = gl.createProgram(); gl.attachShader(program, vs); gl.attachShader(program, fs);
                gl.bindAttribLocation(program, 0, 'p'); gl.linkProgram(program); gl.useProgram(program);
                const buffer = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
                gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 1,-1, 0,1]), gl.STATIC_DRAW);
                gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
                gl.drawArrays(gl.TRIANGLES, 0, 3); gl.finish();
                const pixel = new Uint8Array(4); gl.readPixels(8, 8, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, pixel);
                return JSON.stringify({ ok: gl.getError() === gl.NO_ERROR,
                  pixel: Array.from(pixel), linked: gl.getProgramParameter(program, gl.LINK_STATUS) }); })()
              """)
            if let encoded = result as? String, let data = encoded.data(using: .utf8),
               let values = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               values["ok"] as? Bool == true, values["linked"] as? Bool == true,
               let pixel = values["pixel"] as? [Int], pixel.count == 4,
               pixel[0] > 200, pixel[1] < 50, pixel[2] < 50 { return }
            try await Task.sleep(for: .milliseconds(100))
        } while Date() < deadline
        XCTFail("WebGL triangle readback failed; result: \(String(describing: result))")
    }
}
