import 'package:flutter/material.dart';
import '../services/feed_service.dart';
import '../screens/fan_widgets.dart';

/// Clubs fans can pick as their crest cover (API-Sports team ids). Clubs from
/// the live fixtures list are added on top of these automatically.
const fanClubChoices = <String, String>{
  'AC Milan': '489',
  'AFC Bournemouth': '35',
  'Ajax': '194',
  'Al Ahly': '1029',
  'Al Hilal': '2932',
  'Al Ittihad': '2938',
  'Al Nassr': '2939',
  'Alavés': '542',
  'Almería': '723',
  'Anderlecht': '554',
  'Angers': '77',
  'Arsenal': '42',
  'Aston Villa': '66',
  'Atalanta': '499',
  'Athletic Club': '531',
  'Atlético Madrid': '530',
  'Augsburg': '170',
  'Auxerre': '108',
  'Barcelona': '529',
  'Bayer Leverkusen': '168',
  'Bayern Munich': '157',
  'Benfica': '211',
  'Beşiktaş': '549',
  'Boca Juniors': '451',
  'Bochum': '176',
  'Bologna': '500',
  'Borussia Dortmund': '165',
  'Borussia Mönchengladbach': '163',
  'Brentford': '55',
  'Brest': '106',
  'Brighton': '51',
  'Burnley': '44',
  'Cagliari': '490',
  'Celta Vigo': '538',
  'Celtic': '247',
  'Chelsea': '49',
  'Club Brugge': '569',
  'Como': '895',
  'Cremonese': '520',
  'Crystal Palace': '52',
  'Eintracht Frankfurt': '169',
  'Elche': '797',
  'Empoli': '511',
  'Espanyol': '540',
  'Everton': '45',
  'FC Köln': '192',
  'Fenerbahçe': '611',
  'Feyenoord': '209',
  'Fiorentina': '502',
  'Flamengo': '127',
  'Freiburg': '160',
  'Fulham': '36',
  'Galatasaray': '645',
  'Genoa': '495',
  'Getafe': '546',
  'Girona': '547',
  'Granada': '715',
  'Hamburger SV': '175',
  'Heidenheim': '180',
  'Hellas Verona': '504',
  'Hoffenheim': '167',
  'Holstein Kiel': '191',
  'Hull City': '64',
  'Inter Miami': '9568',
  'Inter Milan': '505',
  'Ipswich Town': '57',
  'Juventus': '496',
  'Las Palmas': '534',
  'Lazio': '487',
  'Le Havre': '111',
  'Lecce': '867',
  'Leeds United': '63',
  'Leicester City': '46',
  'Lens': '116',
  'Levante': '539',
  'Lille': '79',
  'Liverpool': '40',
  'Lorient': '97',
  'Luton Town': '1359',
  'Lyon': '80',
  'Mainz 05': '164',
  'Mallorca': '798',
  'Manchester City': '50',
  'Manchester United': '33',
  'Marseille': '81',
  'Metz': '112',
  'Monaco': '91',
  'Montpellier': '82',
  'Monza': '1579',
  'Nantes': '83',
  'Napoli': '492',
  'Newcastle United': '34',
  'Nice': '84',
  'Nottingham Forest': '65',
  'Olympiacos': '553',
  'Osasuna': '727',
  'Palmeiras': '121',
  'Paris Saint-Germain': '85',
  'Parma': '523',
  'Pisa': '801',
  'Porto': '212',
  'PSV Eindhoven': '197',
  'Rangers': '257',
  'Rayo Vallecano': '728',
  'RB Leipzig': '173',
  'Real Betis': '543',
  'Real Madrid': '541',
  'Real Oviedo': '718',
  'Real Sociedad': '548',
  'Real Valladolid': '720',
  'Reims': '93',
  'Rennes': '94',
  'River Plate': '435',
  'Roma': '497',
  'Sassuolo': '488',
  'Sevilla': '536',
  'Shakhtar Donetsk': '550',
  'Sheffield United': '62',
  'Southampton': '41',
  'Sporting CP': '228',
  'St. Pauli': '186',
  'Strasbourg': '95',
  'Stuttgart': '172',
  'Sunderland': '746',
  'Torino': '503',
  'Tottenham Hotspur': '47',
  'Toulouse': '96',
  'Trabzonspor': '998',
  'Udinese': '494',
  'Union Berlin': '182',
  'Valencia': '532',
  'Villarreal': '533',
  'Werder Bremen': '162',
  'West Ham United': '48',
  'Wolfsburg': '161',
  'Wolverhampton Wanderers': '39',
  'Zamalek': '1031',
};

Future<MapEntry<String, String>?> chooseFanClub(BuildContext context) async {
  final clubs = Map<String, String>.from(fanClubChoices);
  try {
    for (final f in await FeedService().loadFixtures(remote: false)) {
      // A club already listed under another spelling ("Tottenham" vs
      // "Tottenham Hotspur") is not listed twice.
      for (final (name, logo) in [(f.home, f.homeLogo), (f.away, f.awayLogo)]) {
        if (RegExp(r'^\d{1,8}$').hasMatch(logo) && !clubs.containsValue(logo)) {
          clubs[name] = logo;
        }
      }
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
