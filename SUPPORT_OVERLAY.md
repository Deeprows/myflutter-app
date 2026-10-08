# "We Need Your Support" overlay (free plan ads)

Shown to **Free** users after every **15 minutes of use**
(`AppConfig.adIntervalMinutes`). Premium users never see it - see
SUBSCRIPTIONS.md.

The old trigger (tapping a fixture / highlight / movie card, once every 12
hours) is **switched off**: `AppConfig.supportOnCardTap = false`. Set it to
`true` to bring it back (its message then still says "15 minutes").

Settings (lib/config.dart):

| Setting                | Meaning                                              |
|------------------------|------------------------------------------------------|
| `supportUrl`           | Page opened by CLICK HERE. **Empty = no ads at all**  |
| `adIntervalMinutes`    | Minutes of use between overlays (15)                 |
| `supportViewSeconds`   | Page auto-closes after this many seconds (13)        |
| `adRetryMinutes`       | If the page can't load, ask again after this (3)     |

Behaviour: the clock runs only while the app is open on screen, is saved
between launches, and pauses on the plans / payment pages. The overlay opens
on top of whatever is showing (including a stream). The 13 s countdown starts
once the page has loaded. Closing the page early returns to the overlay
(nothing is counted). There is no "Not now" button, but there is a
**Remove ads - go Premium** button. If the page cannot load at all (offline /
dead link) the person is let through. Colours follow the selected app theme.
