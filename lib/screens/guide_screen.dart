import 'package:flutter/material.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../utils/l10n.dart';

/// "Instructions": how to use Deeprowss, posting rules, AI Predict usage,
/// predictions, ranks and rewards. Opened from the side menu and from the
/// icon on every Fan Zone profile.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const GuideScreen()));

  static const _gold = Color(0xFFFFB300);
  static const _blue = Color(0xFF42A5F5);
  static const _violet = Color(0xFFAB47BC);
  static const _orange = Color(0xFFFF7043);
  static const _teal = Color(0xFF26C6DA);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Ui.bg,
      appBar: AppBar(title: Text('Instructions'.tr)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          children: [
            _hero(),
            const SizedBox(height: 14),
            _Section(
              icon: Icons.rocket_launch_rounded,
              color: _blue,
              title: 'Getting started',
              initiallyOpen: true,
              children: const [
                _P('Open the side menu (top-left) to reach everything in the app:'),
                _B('Live Now: matches that are on or about to start.'),
                _B('Football Highlights: goals and match recaps.'),
                _B('TV Channels, Movies, Network Stream and Playlists.'),
                _B('Football Score and Cricket Score: live scores.'),
                _B('Fan Zone: predictions, ranks, community posts and match chats.'),
                _P('Sign in with Gmail to join the Fan Zone. There is no password: '
                    'just tap "Continue with Gmail". Only Gmail accounts work.'),
              ],
            ),
            _Section(
              icon: Icons.play_circle_fill_rounded,
              color: Ui.red,
              title: 'Watching a match',
              children: const [
                _N(1, 'Open a match from Live Now.'),
                _N(2, 'Double tap the screen to start playing.'),
                _N(3, 'Stream not working? Tap another stream number '
                    '(1, 2, 3, 4) beside "Stream".'),
                _N(4, 'Use the reload icon to try the same stream again and the '
                    'rotate icon to switch between portrait and landscape.'),
                _N(5, 'Chat with other fans in Live chat under the player.'),
                _Note('Streams come from third-party sources. If every number '
                    'fails, wait a little and reload; the match may not have '
                    'started yet.'),
              ],
            ),
            _Section(
              icon: Icons.edit_note_rounded,
              color: _teal,
              title: 'Posting in the Fan Zone',
              children: [
                const _P('You can publish four kinds of post:'),
                const _B('Prediction: call a score or a player moment before kick-off.'),
                const _B('Betslip: show your slip. Crop out account details first.'),
                const _B('Banter: share a hot take with the community.'),
                const _B('Video: share a YouTube, Vimeo, Dailymotion or Filemoon '
                    'link, a stream link (m3u8, mp4, mpd) or any embed page.'),
                const SizedBox(height: 6),
                const _Sub('Limits'),
                const _B('Post text: up to 5,000 characters.'),
                const _B('Video title: up to 100 characters; video note: up to 1,000.'),
                const _B('Images: smaller than 4 MB.'),
                const _B('Replies (comments): up to 500 characters.'),
                const _B('Match chat messages: up to 300 characters.'),
                const _B('TikTok and Facebook videos cannot be embedded.'),
                const SizedBox(height: 6),
                const _Sub('Rules'),
                const _B('Be respectful. No hate speech, threats, harassment or bullying.'),
                const _B('No adult, violent or illegal content.'),
                const _B('No spam, repeated posts, scams or unwanted promotions.'),
                const _B('Never post private details: yours or anyone else\u2019s '
                    '(phone numbers, bank or account details, passwords).'),
                const _B('Do not impersonate other people or the Deeprowss team.'),
                const _B('Do not post content you do not have the right to share.'),
                const _B('Predictions are opinions, not guarantees. Never ask '
                    'others to send money.'),
                const _B('Match chat and names: pick a unique name (you cannot '
                    'change it later) and you must be 18 or older.'),
                const _Note('Your Fan Zone name and posts are public. Your Gmail '
                    'stays private.'),
                const SizedBox(height: 6),
                const _Sub('Managing posts'),
                const _B('Anyone can delete their own post.'),
                const _B('Premium members can also edit their posts and comments '
                    'after publishing.'),
                const _B('See something wrong? Open the post menu and tap '
                    '"Report post" or "Report comment" so it can be reviewed.'),
                const _B('"Hide fan on this device" removes a fan\u2019s posts from '
                    'your feed. Unblock from the notice at the top of the feed.'),
                const _P('Posts that break these rules may be removed and '
                    'repeat offenders may be restricted.'),
              ],
            ),
            _Section(
              icon: Icons.sports_soccer_rounded,
              color: Ui.green,
              title: 'Predictions and points',
              children: [
                const _N(1, 'Open Fan Zone and choose Predict.'),
                const _N(2, 'Pick a winner, a draw, or the exact score before '
                    'the match starts.'),
                const _N(3, 'Your pick locks at kick-off, so it cannot be changed '
                    'after the match begins.'),
                const _N(4, 'When the match ends, the final score is checked and '
                    'your points are added to the Ranks table.'),
                const SizedBox(height: 8),
                _points(),
                const SizedBox(height: 8),
                const _B('If a match is cancelled or postponed, your pick is '
                    'refunded and you neither win nor lose points.'),
                const _B('A pick shows "Pending" until the final score is '
                    'confirmed. This can take a little while after full time.'),
                const _B('You get a notification when a pick is settled.'),
                const _B('Your streak counts how many settled picks in a row '
                    'earned points.'),
              ],
            ),
            _Section(
              icon: Icons.auto_awesome_rounded,
              color: _violet,
              title: 'AI Predict',
              children: const [
                _P('AI Predict studies teams, recent form and head-to-head '
                    'results and gives you an analysis with suggested picks.'),
                _N(1, 'Open AI Predict and choose the matches you want '
                    'analysed. Upcoming matches from many leagues are listed.'),
                _N(2, 'Can\u2019t find a match? Type the matchup yourself, for '
                    'example "Arsenal vs Chelsea". National teams work too.'),
                _N(3, 'Tap to generate the analysis and read the breakdown.'),
                _N(4, 'Save the picks you like so they count in the Fan Zone '
                    'and appear under your saved picks.'),
                _Sub('Daily use'),
                _B('Free users can select up to 3 matches per day.'),
                _B('The counter at the bottom shows how many are left today '
                    'and resets the next day.'),
                _B('Premium members, including weekly Ranks winners, can '
                    'select more matches.'),
                _Note('AI analysis is guidance only, not a guarantee. Football '
                    'is unpredictable, so never risk money you cannot afford '
                    'to lose.'),
              ],
            ),
            _Section(
              icon: Icons.leaderboard_rounded,
              color: _gold,
              title: 'Ranks and rewards',
              children: [
                const _P('The Ranks table lists fans by points. Columns: '
                    'P (picks played), W (won), L (lost) and PTS (points).'),
                const _B('Gold, silver and bronze mark the top three places.'),
                const _B('Tap any fan in the table to open their profile.'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      _gold.withValues(alpha: .22),
                      _gold.withValues(alpha: .06),
                    ]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _gold.withValues(alpha: .35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events_rounded,
                          color: _gold, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Weekly reward',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900, fontSize: 14.5)),
                            const SizedBox(height: 2),
                            Text(
                              'The top 3 fans each week win 7 days of Premium '
                              'and a blue tick.',
                              style: TextStyle(
                                  color: Ui.muted, fontSize: 12.5, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                const _B('Winners are announced in Ranks under "Weekly winners". '
                    'Earlier weeks stay listed.'),
                const _B('Premium rewards are activated on the winner\u2019s '
                    'account automatically.'),
                const _B('Cheating, fake accounts or abusing the system can '
                    'lead to disqualification and loss of rewards.'),
                const _Sub('What Premium (and the blue tick) gives you'),
                const _B('A blue verified tick beside your name.'),
                const _B('Edit your posts and comments after publishing.'),
                const _B('More AI Predict selections per day.'),
              ],
            ),
            _Section(
              icon: Icons.workspace_premium_rounded,
              color: _orange,
              title: 'Ads, Premium and tokens',
              children: [
                _P(('Free users see a short "We Need Your Support" page after '
                        'every {n} minutes of use. Wait '
                        'for Skip Ad to appear and tap it to carry on.')
                    .trArgs({'n': AppConfig.adIntervalMinutes})),
                const _B('Want fewer interruptions? Open "Remove ads" in the '
                    'menu and tap "Request token". Once you receive your '
                    'token, enter it to remove ads on that phone for the '
                    'number of days given.'),
                const _B('Movies: some titles need Premium to play or download.'),
              ],
            ),
            _Section(
              icon: Icons.support_agent_rounded,
              color: _blue,
              title: 'Need help?',
              children: const [
                _B('Menu \u203A Contact Us opens a chat with the admin.'),
                _B('Menu \u203A Notice shows the latest announcements.'),
                _B('Menu \u203A Update App checks for a new version.'),
                _B('Join Us opens our community channel.'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Ui.red.withValues(alpha: .28),
              Ui.red.withValues(alpha: .06),
            ],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Ui.red.withValues(alpha: .35)),
        ),
        child: Row(
          children: [
            Icon(Icons.menu_book_rounded, size: 34, color: Ui.red),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How Deeprowss works'.tr,
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(
                    ('Using the app, posting rules, AI Predict, predictions, '
                            'ranks and rewards. Tap a section to open it.')
                        .tr,
                    style:
                        TextStyle(color: Ui.muted, fontSize: 12.5, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _points() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        decoration: BoxDecoration(
          color: Ui.cardDeep,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ui.line),
        ),
        child: Row(
          children: [
            _pt(Icons.track_changes_rounded, '+3', 'Exact score', Ui.green),
            _div(),
            _pt(Icons.check_circle_outline_rounded, '+1', 'Right winner / draw',
                _blue),
            _div(),
            _pt(Icons.close_rounded, '0', 'Missed', const Color(0xFFEF5350)),
          ],
        ),
      );

  Widget _div() => Container(width: 1, height: 38, color: Ui.line);

  Widget _pt(IconData icon, String big, String small, Color c) => Expanded(
        child: Column(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(height: 3),
            Text(big,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w900, color: c)),
            Text(small.tr,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: Ui.muted)),
          ],
        ),
      );
}

// ---------------------------------------------------------------- building blocks

class _Section extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> children;
  final bool initiallyOpen;
  const _Section({
    required this.icon,
    required this.color,
    required this.title,
    required this.children,
    this.initiallyOpen = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Ui.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Ui.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: initiallyOpen,
              tilePadding: const EdgeInsets.symmetric(horizontal: 14),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              title: Text(title.tr,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w800)),
              children: children,
            ),
          ),
        ),
      );
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(text.tr,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: Ui.text)),
      );
}

class _Sub extends StatelessWidget {
  final String text;
  const _Sub(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 5),
        child: Text(text.tr.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                letterSpacing: .6,
                fontWeight: FontWeight.w900,
                color: Ui.muted)),
      );
}

class _B extends StatelessWidget {
  final String text;
  const _B(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 9, left: 2),
              child: Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: Ui.red, shape: BoxShape.circle),
              ),
            ),
            Expanded(
              child: Text(text.tr,
                  style:
                      TextStyle(fontSize: 13.5, height: 1.45, color: Ui.text)),
            ),
          ],
        ),
      );
}

class _N extends StatelessWidget {
  final int n;
  final String text;
  const _N(this.n, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Ui.red, shape: BoxShape.circle),
              child: Text('$n',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.black)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(text.tr,
                  style:
                      TextStyle(fontSize: 13.5, height: 1.45, color: Ui.text)),
            ),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  final String text;
  const _Note(this.text);
  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1877F2);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: blue.withValues(alpha: Ui.isLight ? .08 : .16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: blue.withValues(alpha: .35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.info_rounded, size: 15, color: blue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text.tr,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: Ui.text)),
          ),
        ],
      ),
    );
  }
}
