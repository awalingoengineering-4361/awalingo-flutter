# APK issue 34: offline handling

Source: [Native App Dev Tracker, APK issue 34](https://docs.google.com/spreadsheets/d/1U4m63Nxz83NcFxk1vNpQrjTZhtYsb7NJ4kbqg7XCg-g/edit?gid=0).

Failed internet requests must not appear as raw errors, empty data, partial
forms, or fallback language labels. The affected surfaces are AwaQuiz,
Voting/Jury and Translation lounges, Curator Test, AwaDiko, Request a Word,
and Word Requests.

Acceptance:
- Connection failures display **You are offline**, **Retry**, and proposed copy:
  “Please check your internet connection and reconnect with your mother tongue community.”
- Server, permission, and parse failures get a generic load-error state,
  distinct from both offline errors and genuine empty responses.
- Failed bootstrap hides controls that require language IDs or part-of-speech
  data. Retry repeats bootstrap instead of using COM/EN or NEO/EN defaults.
- Failed pagination preserves loaded dictionary terms and retries the same page.
- Network failure preserves entered form text. Retry actions only repeat reads;
  they never automatically replay submissions, votes, or quiz attempts.
- Repeating offline → reconnect → Retry works for the same user. Late responses
  must not overwrite newer results or update disposed screens, and retries
  must not duplicate dictionary entries or curator-test timers.

Boundaries: one issue and one focused PR. Offline data storage, push delivery,
quiz scoring, reward transactions, and role promotion are outside this change.
