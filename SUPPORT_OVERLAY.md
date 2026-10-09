# Ads for the free plan: "ad support" page (overlay temporarily hidden)

**Current behaviour** (`AppConfig.supportOverlayVisible = false`): the "We Need
Your Support" overlay is hidden. On the **first tap of each launch** on a
fixture, highlight, TV channel, movie, a play button in the Player tab (phone
videos / music), a network stream, or a movie in My Library - and then every
10 minutes of use - `supportUrl` opens full screen under a slim bar that says
**"Ad support timeout: please wait"** (`supportWaitText`).

* The page is **never cut off while it is loading** - no close button, Back is
  ignored.
* When it has fully loaded (redirects included) the bar changes to "Ad loaded
  · back in Ns" with a **Resume** button. The page can be used meanwhile.
* After `supportAfterLoadSeconds` (5) it closes by itself, or earlier when
  Resume / Back is tapped, and the person is back where they were; the tapped
  item then opens.
* If the person opens another page from the ad, the wait message returns until
  that page has loaded too.
* A page that never reports "finished" is treated as loaded after
  `supportMaxLoadSeconds` (40). If nothing loads at all (offline / dead link)
  the person can Retry or Continue - nobody is locked out.
* No "Thanks" banner (`supportThanksBanner = false`).

Set `supportOverlayVisible = true` to bring the old overlay (below) back.

---

# "We Need Your Support" overlay (the hidden one)

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
| `supportOverlayVisible`| false = overlay hidden, ad page opens directly       |
| `supportWaitText`      | Message while the ad page loads                      |
| `supportAfterLoadSeconds` | Seconds the page stays after it has fully loaded (5) |
| `supportMaxLoadSeconds`| Safety cap for a page that never finishes loading (40)|
| `supportThanksBanner`  | Show the "Thanks" banner afterwards (false)          |
| `adRetryMinutes`       | If the page can't load, ask again after this (3)     |
| `showSubscriptions`    | false = Premium hidden everywhere (ads stay on)      |

The clock runs only while the app is open on screen and is saved between
launches. The overlay opens on top of whatever is showing. There is no
"Not now" button. If the page cannot load at all the person is let through.
