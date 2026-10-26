import 'package:flutter/material.dart';
import '../services/feed_service.dart';
import '../screens/fan_widgets.dart';

const fanClubChoices = <String, String>{
  'AFC Bournemouth': '35',
  'Athletic Club': '531',
  'Barcelona': '529',
  'Bayer Leverkusen': '168',
  'Bayern Munich': '157',
  'Brentford': '55',
  'Brighton': '51',
  'Celta Vigo': '538',
  'Crystal Palace': '52',
  'Fenerbahçe': '611',
  'Freiburg': '160',
  'Galatasaray': '645',
  'Getafe': '546',
  'Hoffenheim': '167',
  'Hull City': '64',
  'Leeds United': '63',
  'Levante': '539',
  'Liverpool': '40',
  'Lyon': '80',
  'Manchester United': '33',
  'Newcastle United': '34',
  'Osasuna': '727',
  'Paris Saint-Germain': '85',
  'Real Betis': '543',
  'Real Madrid': '541',
  'Real Sociedad': '548',
  'Sevilla': '536',
  'Sunderland': '746',
};

Future<MapEntry<String, String>?> chooseFanClub(BuildContext context) async {
  final clubs = Map<String, String>.from(fanClubChoices);
  try {
    for (final f in await FeedService().loadFixtures(remote: false)) {
      if (RegExp(r'^\d{1,8}$').hasMatch(f.homeLogo)) clubs[f.home] = f.homeLogo;
      if (RegExp(r'^\d{1,8}$').hasMatch(f.awayLogo)) clubs[f.away] = f.awayLogo;
    }
  } catch (_) {}
  if (!context.mounted) return null;
  String search = '';
  return showModalBottomSheet<MapEntry<String, String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .75,
        child: Column(
          children: [
            const Text(
              'Choose your club',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: false,
                onChanged: (v) => set(() => search = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search clubs',
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    title: const Text('No club / use my uploaded cover'),
                    onTap: () => Navigator.pop(
                      ctx,
                      const MapEntry<String, String>('', ''),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Another club'),
                    subtitle: const Text(
                      'Enter a name and upload its cover in Edit profile',
                    ),
                    onTap: () async {
                      String name = '';
                      final picked = await showDialog<String>(
                        context: ctx,
                        builder: (dialog) => AlertDialog(
                          title: const Text('Your club'),
                          content: TextField(
                            maxLength: 60,
                            onChanged: (v) => name = v.trim(),
                            decoration: const InputDecoration(
                              hintText: 'Club name',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, name),
                              child: const Text('Select'),
                            ),
                          ],
                        ),
                      );
                      if (picked != null && picked.isNotEmpty && ctx.mounted)
                        Navigator.pop(
                          ctx,
                          MapEntry<String, String>(picked, ''),
                        );
                    },
                  ),
                  for (final c
                      in (clubs.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key))))
                    if (c.key.toLowerCase().contains(search.toLowerCase()))
                      ListTile(
                        leading: TeamCrest(logo: c.value, size: 36),
                        title: Text(c.key),
                        onTap: () => Navigator.pop(ctx, c),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class FanClubCover extends StatelessWidget {
  final String name, logo;
  const FanClubCover({super.key, required this.name, required this.logo});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(colors: [Color(0xFF252F48), Color(0xFF080B15)]),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            name,
            maxLines: 2,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 20),
        TeamCrest(logo: logo, size: 100),
      ],
    ),
  );
}
