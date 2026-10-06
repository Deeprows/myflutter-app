# "We Need Your Support" overlay

Appears when a **fixture card**, **highlight card** or **movie card** is tapped,
at most once every 12 hours. After the support page closes, a "Thanks 💗"
banner shows and the tapped card opens as normal.

Settings (lib/config.dart):

| Setting                   | Meaning                                              |
|---------------------------|------------------------------------------------------|
| `supportUrl`              | Page opened by CLICK HERE. **Empty = overlay is off** |
| `supportIntervalHours`    | Time between overlays after a completed visit (12)   |
| `supportViewSeconds`      | Page auto-closes after this many seconds (13)        |
| `supportRetryHours`       | If the support page can't load, ask again after (1)  |

Behaviour: the 13 s countdown starts once the page has loaded. Closing the
page early returns to the overlay (nothing is counted). There is no
"Not now" button; if the page cannot load at all (offline / dead link) the
person is let through so nobody is locked out. Colours follow the
selected app theme.
