# Accounts and Notifications

How to connect a mailbox and choose how the app tells you about new mail.

---

## Adding an account

Open the account wizard on first launch, or from Settings → Accounts. There are two ways in:

- **Password or app password (IMAP/SMTP).** Enter your address and password; the server settings are looked up automatically where possible. Works with any standard provider.
- **Continue with Google / Continue with Microsoft.** The app opens your system browser (or a browser sheet on iOS, Android and macOS) so you sign in at Google or Microsoft directly. DataFortress never sees your password.

The Google and Microsoft buttons are always shown. In a build compiled without client IDs, tapping one shows "Google sign-in is not configured in this build" (or the Microsoft equivalent) and password accounts keep working. See [Configuration](configuration.md#3-oauth-client-ids-google-and-microsoft-sign-in).

Notes:

- Tokens are kept in the platform secure store and removed with the account. See [Google and Microsoft Sign-In](../concepts/privacy-model.md#google-and-microsoft-sign-in).
- Many company (work or school) Microsoft tenants disable IMAP/SMTP access; in that case only personal outlook.com, hotmail and live accounts connect.
- Google restricted-scope rules: until the app is verified by Google, sign-in is limited to 100 users and shows an "unverified app" screen.

### Reconnect

If you change your password or revoke access, the provider refuses the saved token. The account is then marked as needing sign-in and Settings → Accounts shows a **Reconnect** action. Tapping it repeats the browser sign-in; mail already downloaded is kept.

---

## New-mail notifications

Settings → **Notifications** picks one of four modes (default: *On every new message*):

| Mode | Behaviour |
|---|---|
| Off | No notifications. |
| On every new message | One notification per new message. |
| Bundled every 5 minutes | One summary notification listing the senders, at most every 5 minutes. |
| Hourly summary | One summary notification per hour. |

Which mail notifies: a message that is new in the Inbox on this sync, unread, not part of a folder's first fetch (adding an account does not flood you), classified Inbox or ham, with a spam score below 0.6. Spam, newsletters, Sent mail and mail imported by a search never notify. A notification shows the sender and subject only, never message text. Tapping one opens that message.

**Send test notification** in the same screen checks that delivery works. If the OS refused permission, the screen says notifications are blocked in system settings; the OS permission is requested after an in-app explanation.

!!! note "Only while the app runs"
    Notifications are raised on the device by the running app (shared `df_notifications`, over `flutter_local_notifications`). There is no mobile background fetch or push service, so nothing arrives while the app is fully closed. Accounts are checked every 60 seconds in *On every new message* mode and every 5 minutes otherwise.
