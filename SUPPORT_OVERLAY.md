# "We Need Your Support" overlay (free plan ads)

Shown to **Free** users:

1. on the **first tap** (each time the app is opened) on a fixture, a highlight,
   a TV channel or a movie, and
2. after that **every 10 minutes of use** (`AppConfig.adIntervalMinutes`).

Completing the first-tap overlay restarts the 10-minute clock. Premium users
never see it (see SUBSCRIPTIONS.md). Both use the same overlay: CLICK HERE
opens the page in the in-app browser, it closes by itself after 13 s, then a
"Thanks" banner appears. Colours follow the selected app theme.

The page opened by CLICK HERE is fully tappable: links that open a new
tab/window open in the same page, and app links (intent://, market://) are
turned into their web page.

Settings (lib/config.dart):

| Setting                | Meaning                                              |
|------------------------|------------------------------------------------------|
| `supportUrl`           | Page opened by CLICK HERE. **Empty = no ads at all**  |
| `adIntervalMinutes`    | Minutes of use between overlays (10)                 |
| `supportOnFirstTap`    | First tap of each launch shows the overlay (true)    |
| `supportViewSeconds`   | Page auto-closes after this many seconds (13)        |
| `adRetryMinutes`       | If the page can't load, ask again after this (3)     |
| `showSubscriptions`    | false = Premium hidden everywhere (ads stay on)      |

The clock runs only while the app is open on screen and is saved between
launches. The overlay opens on top of whatever is showing. There is no
"Not now" button. If the page cannot load at all the person is let through.
