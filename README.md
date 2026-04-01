# GCal

Tired of opening Google Calendar in the browser? GCal is a lightweight / minimal macOS app that wraps Google Calendar in a native window. 

<p align="center">
<img src="assets/dock.png" width="500" alt="GCal in the Dock">
<br><br>
<img src="assets/menubar.png" width="300" alt="Menu bar dropdown">
</p>

## Install

```
git clone https://github.com/yourusername/gcal-app.git
cd gcal-app
make install
```

This builds the app and copies it to `/Applications`. Requires Xcode 15+ and macOS 14+.

## Features

- Native macOS window with Google Calendar embedded
- Menu bar icon showing how many events you have left today
- Persistent login — sign in once, stay signed in

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| Cmd + R | Reload |
| Cmd + [ | Back |
| Cmd + ] | Forward |
| Cmd + Shift + T | Go to Today |

## Menu Bar

The menu bar icon shows a calendar with the number of events remaining today. This uses macOS EventKit, if you want it to reflect your Google Calendar events, add your Google account in **System Settings > Internet Accounts**.

Click the menu bar icon to quickly open the calendar window or quit the app.

## How It Works

The app loads `calendar.google.com` inside a [WKWebView](https://developer.apple.com/documentation/webkit/wkwebview) (the same WebKit engine Safari uses). The user agent is set to Safari so Google's sign-in flow works normally.

Sessions persist between launches via WebKit's default persistent data store, the same mechanism Safari uses for cookies.

- **No cookie access** — login tokens are managed entirely by WebKit
- **No analytics or telemetry** — zero third-party code
- **No network interception** — all traffic goes directly through WebKit over HTTPS

The full app is ~200 lines of Swift. Read it yourself: [GCalApp.swift](GCalApp/GCalApp.swift) and [CalendarWebView.swift](GCalApp/CalendarWebView.swift).

## License

MIT

Google Calendar is a trademark of Google LLC. This project is not affiliated with or endorsed by Google.
