# Issue 101: notification click actions

Tapping a notification should open its linked native item. General announcements
that link to /notifications currently open another copy of the list, and null or
unsupported links silently do nothing after the read indicator changes. The web
backend defaults announcements to /notifications; Flutter needs a readable item
view for these cases.

Reuse the native destinations already mapped by notification_router.dart.
For a notification with no native destination, open a themed detail screen with
its complete title, message and date. A /notifications link opens this item's
details rather than duplicating the list. Apply the same behavior to the bell
preview and full list. Native push taps without a notification record retain
their existing list fallback.

Read writes remain scoped to the signed-in user and notification ID. Only unread
items need a write. Failed writes leave the item unread and show a retryable
message. Repeated taps must not stack routes or duplicate pending writes; an
account switch or leaving the source while a write/lookup is pending cancels
navigation. No backend or database change, external URL launch, or new admin UI.
