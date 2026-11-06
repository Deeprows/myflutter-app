/// Country (ISO 3166 alpha-2) -> currency (ISO 4217), used to show the
/// Premium price in the person's own money. Anything not listed falls back
/// to US dollars. The Worker does the conversion; this only picks the code.
const Map<String, String> _currencyByCountry = {
  // Africa
  'NG': 'NGN', 'GH': 'GHS', 'KE': 'KES', 'ZA': 'ZAR', 'UG': 'UGX',
  'TZ': 'TZS', 'RW': 'RWF', 'ET': 'ETB', 'EG': 'EGP', 'MA': 'MAD',
  'DZ': 'DZD', 'TN': 'TND', 'ZM': 'ZMW', 'ZW': 'USD', 'MW': 'MWK',
  'MZ': 'MZN', 'AO': 'AOA', 'NA': 'NAD', 'BW': 'BWP', 'LR': 'LRD',
  'SL': 'SLE', 'GM': 'GMD', 'CD': 'CDF', 'MU': 'MUR', 'SD': 'SDG',
  'LY': 'LYD', 'SN': 'XOF', 'CI': 'XOF', 'ML': 'XOF', 'BF': 'XOF',
  'BJ': 'XOF', 'TG': 'XOF', 'NE': 'XOF', 'GW': 'XOF', 'CM': 'XAF',
  'GA': 'XAF', 'CG': 'XAF', 'TD': 'XAF', 'GQ': 'XAF', 'CF': 'XAF',
  // Europe
  'GB': 'GBP', 'CH': 'CHF', 'SE': 'SEK', 'NO': 'NOK', 'DK': 'DKK',
  'PL': 'PLN', 'CZ': 'CZK', 'HU': 'HUF', 'RO': 'RON', 'BG': 'BGN',
  'TR': 'TRY', 'UA': 'UAH', 'RU': 'RUB', 'IS': 'ISK',
  'DE': 'EUR', 'FR': 'EUR', 'ES': 'EUR', 'IT': 'EUR', 'NL': 'EUR',
  'BE': 'EUR', 'PT': 'EUR', 'IE': 'EUR', 'AT': 'EUR', 'FI': 'EUR',
  'GR': 'EUR', 'HR': 'EUR', 'SK': 'EUR', 'SI': 'EUR', 'LU': 'EUR',
  // Americas
  'US': 'USD', 'CA': 'CAD', 'MX': 'MXN', 'BR': 'BRL', 'AR': 'ARS',
  'CL': 'CLP', 'CO': 'COP', 'PE': 'PEN', 'JM': 'JMD', 'TT': 'TTD',
  // Asia / Middle East / Oceania
  'IN': 'INR', 'PK': 'PKR', 'BD': 'BDT', 'LK': 'LKR', 'NP': 'NPR',
  'CN': 'CNY', 'JP': 'JPY', 'KR': 'KRW', 'ID': 'IDR', 'MY': 'MYR',
  'SG': 'SGD', 'TH': 'THB', 'VN': 'VND', 'PH': 'PHP', 'HK': 'HKD',
  'AE': 'AED', 'SA': 'SAR', 'QA': 'QAR', 'KW': 'KWD', 'BH': 'BHD',
  'OM': 'OMR', 'IL': 'ILS', 'JO': 'JOD', 'LB': 'LBP', 'IQ': 'IQD',
  'AU': 'AUD', 'NZ': 'NZD',
};

/// Currency code for a country code ('NG' -> 'NGN'). Unknown or missing
/// countries get 'USD'.
String currencyForCountry(String? countryCode) {
  final c = (countryCode ?? '').toUpperCase();
  return _currencyByCountry[c] ?? 'USD';
}

/// Countries offered in the "Pricing country / currency" picker of the
/// Remove ads page: (country code, name). The currency comes from
/// [currencyForCountry].
const List<List<String>> kPricingCountries = [
  ['NG', 'Nigeria'], ['GH', 'Ghana'], ['KE', 'Kenya'], ['ZA', 'South Africa'],
  ['UG', 'Uganda'], ['TZ', 'Tanzania'], ['RW', 'Rwanda'], ['ET', 'Ethiopia'],
  ['EG', 'Egypt'], ['MA', 'Morocco'], ['DZ', 'Algeria'], ['TN', 'Tunisia'],
  ['ZM', 'Zambia'], ['SN', 'Senegal'], ['CI', "Côte d'Ivoire"],
  ['CM', 'Cameroon'], ['GB', 'United Kingdom'], ['DE', 'Germany'],
  ['FR', 'France'], ['ES', 'Spain'], ['IT', 'Italy'], ['NL', 'Netherlands'],
  ['PT', 'Portugal'], ['IE', 'Ireland'], ['CH', 'Switzerland'],
  ['SE', 'Sweden'], ['NO', 'Norway'], ['PL', 'Poland'], ['TR', 'Türkiye'],
  ['US', 'United States'], ['CA', 'Canada'], ['MX', 'Mexico'],
  ['BR', 'Brazil'], ['AR', 'Argentina'], ['CO', 'Colombia'],
  ['IN', 'India'], ['PK', 'Pakistan'], ['BD', 'Bangladesh'],
  ['ID', 'Indonesia'], ['MY', 'Malaysia'], ['SG', 'Singapore'],
  ['PH', 'Philippines'], ['TH', 'Thailand'], ['VN', 'Vietnam'],
  ['AE', 'United Arab Emirates'], ['SA', 'Saudi Arabia'], ['QA', 'Qatar'],
  ['KW', 'Kuwait'], ['JO', 'Jordan'], ['AU', 'Australia'],
  ['NZ', 'New Zealand'],
];

/// "Egypt" for 'EG'; the code itself when it is not in the picker list.
String countryName(String? countryCode) {
  final c = (countryCode ?? '').toUpperCase();
  for (final e in kPricingCountries) {
    if (e[0] == c) return e[1];
  }
  return c.isEmpty ? 'your region' : c;
}
