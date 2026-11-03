# Only Chat and 3F policy candidates retention receipt

- Built a fresh Only Chat Mac candidate at `/Users/rogan/.gemini/antigravity/scratch/my-codex/.build/Only Chat Policy Candidate.app` from the current source root. It embeds the current native WebKit shell and loads the updated local server route from that root. Bundle port is 8899.
- Built a fresh 3F Browser release candidate at `/Users/rogan/appDev/apps/3f-browser-mac/.build/policy-candidate/3F Browser.app`, including the new Only Chat Focus Fence policy request in its control API.
- Both candidates passed strict deep code-signature verification; Only Chat also passed `workflow-control verify-mac` in local_dev mode. Neither candidate was launched, installed over, or substituted for a running app.
- Retained the earlier embedded UI candidate at `.build/Only Chat 3F Embedded Candidate.app`; it was not active and was not deleted.
- Existing installed Only Chat PID 52674 and 3F Browser PID 88092 remained running. The old Only Chat Node server PID 52680 still returns 404 because it loaded before the current route source. No session was restarted.
- Disk output is 1.0M for Only Chat candidate and 1.3M for 3F candidate; release/test compilation reused existing `.build` trees. No temporary verification directory was created.
- Chrome extension coverage remains incomplete: current product uses WebKit; separate Chromium probe is not the 3F product and no store extension was installed or tested.
