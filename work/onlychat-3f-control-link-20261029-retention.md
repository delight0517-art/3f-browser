# 3F control link retention receipt

- Reused the existing Swift package `.build` tree; no second 3F build tree was created and no app was installed or relaunched.
- `swift test` passed all 14 tests, including 3F navigation fail-closed, Focus Fence denial, and HTTP 403/503 response mapping.
- Only Chat focused browser/Focus Fence tests passed 4/4; bridge syntax check passed.
- Existing Only Chat (PID 52674) and 3F Browser (PID 88092) stayed running.
- The live Only Chat server at 127.0.0.1:8899 returned 404 for POST `/api/browser/authorize`; process start was 20:42 while the checked source route was modified at 21:54. This confirms the running process has not loaded the current route. No restart was attempted.
- The current source route is covered by Only Chat's focused `threefBrowserHandoff` HTTP tests. 3F direct navigation now requests that route; 200/allowed proceeds, 403/denied blocks, and service/unexpected responses fail closed.
- No superseded output was removed. Existing embedded candidate was left intact.
