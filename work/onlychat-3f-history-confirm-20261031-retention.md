# Only Chat 3F navigation candidate retention receipt

Task: onlychat-3f-history-confirm-20261031

- Retained the verified local candidate at `.build/onlychat-history-ack-candidate/3F Browser.app` (executable SHA-256 `f44e54a6ab0985be8f96d34695a9c5fc4d2e2850f88693441f05d7ab964e8f46`). It is still needed to reproduce/diagnose the installed-runtime lifetime issue and was not replaced or installed over the user's app.
- The production installed bundle returned control status HTTP 200 at 0.2s and 1s, then its process and control endpoint were gone by 3s. Page navigation/readback on the production installation is therefore incomplete.
- Full repository/source remains canonical and preserved. No old build outputs were pruned because the candidate remains the only retained reproduction artifact for this check.
- Isolated temporary profiles from completed bridge runs were cleaned. Existing Only Chat processes, draft, and the unrelated schedule candidate process were left untouched.
- No installation, app-data migration, or destructive cleanup occurred.
