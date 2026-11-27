/// Legitimate registrable domains for commonly phished brands.
const Map<String, Set<String>> phishedBrands = {
  'paypal': {'paypal.com', 'paypal.de', 'paypal.co.uk', 'paypal.fr'},
  'apple': {'apple.com', 'icloud.com'},
  'microsoft': {'microsoft.com', 'office.com', 'outlook.com', 'live.com', 'hotmail.com'},
  'google': {'google.com', 'google.de', 'google.co.uk', 'gmail.com'},
  'amazon': {'amazon.com', 'amazon.de', 'amazon.co.uk', 'amazon.fr', 'amazon.it', 'amazon.es'},
  'netflix': {'netflix.com'},
  'dhl': {'dhl.com', 'dhl.de'},
  'dpd': {'dpd.com', 'dpd.de'},
  'ups': {'ups.com'},
  'fedex': {'fedex.com'},
  'sparkasse': {'sparkasse.de'},
  'deutsche bank': {'deutsche-bank.de', 'db.com'},
  'commerzbank': {'commerzbank.de', 'commerzbank.com'},
  'ing': {'ing.de', 'ing.com'},
  'n26': {'n26.com'},
  'revolut': {'revolut.com'},
  'chase': {'chase.com'},
  'wellsfargo': {'wellsfargo.com'},
  'bankofamerica': {'bankofamerica.com', 'bofa.com'},
  'coinbase': {'coinbase.com'},
  'binance': {'binance.com'},
  'docusign': {'docusign.com', 'docusign.net'},
  'dropbox': {'dropbox.com'},
  'linkedin': {'linkedin.com'},
  'facebook': {'facebook.com', 'meta.com'},
  'meta': {'meta.com', 'facebook.com'},
  'instagram': {'instagram.com'},
  'whatsapp': {'whatsapp.com'},
  'steam': {'steampowered.com', 'steamcommunity.com'},
  'ebay': {'ebay.com', 'ebay.de', 'ebay.co.uk'},
  'booking': {'booking.com'},
  'airbnb': {'airbnb.com'},
  'adobe': {'adobe.com'},
  'irs': {'irs.gov'},
  'hmrc': {'hmrc.gov.uk', 'gov.uk'},
  'elster': {'elster.de'},
  'postbank': {'postbank.de'},
  'citibank': {'citibank.com', 'citi.com'},
  'santander': {'santander.com', 'santander.co.uk', 'santander.de'},
  'barclays': {'barclays.com', 'barclays.co.uk'},
  'hsbc': {'hsbc.com', 'hsbc.co.uk'},
  'bnp paribas': {'bnpparibas.com', 'bnpparibas.fr'},
  'stripe': {'stripe.com'},
  'square': {'squareup.com', 'square.com'},
  'twitter': {'twitter.com', 'x.com'},
  'x': {'x.com', 'twitter.com'},
  'yahoo': {'yahoo.com'},
  'spotify': {'spotify.com'},
  'uber': {'uber.com'},
  'walmart': {'walmart.com'},
  'target': {'target.com'},
  'costco': {'costco.com'},
  'usps': {'usps.com'},
  'royal mail': {'royalmail.com'},
  'la poste': {'laposte.fr'},
  'kraken': {'kraken.com'},
  'gemini': {'gemini.com'},
  'gitlab': {'gitlab.com'},
  'github': {'github.com'},
  'zoom': {'zoom.us'},
  'salesforce': {'salesforce.com'},
  'intuit': {'intuit.com', 'turbotax.com'},
};

const Set<String> _multiPartTlds = {
  'co.uk', 'org.uk', 'gov.uk', 'ac.uk', 'net.uk',
  'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
  'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'go.jp',
  'co.nz', 'net.nz', 'org.nz',
  'com.br', 'org.br', 'net.br',
  'co.za', 'org.za',
  'com.sg', 'org.sg',
};

/// Extracts the registrable domain (e.g. `sub.example.co.uk` -> `example.co.uk`).
String getRegistrableDomain(String host) {
  final cleanHost = host.trim().toLowerCase().replaceAll(RegExp(r'^www\.'), '');
  if (cleanHost.isEmpty) return '';

  final parts = cleanHost.split('.');
  if (parts.length <= 2) return cleanHost;

  final lastTwo = '${parts[parts.length - 2]}.${parts.last}';
  if (_multiPartTlds.contains(lastTwo) && parts.length >= 3) {
    return '${parts[parts.length - 3]}.$lastTwo';
  }
  return '${parts[parts.length - 2]}.${parts.last}';
}

/// Set of all valid brand registrable domains across phishedBrands.
final Set<String> allBrandDomains = phishedBrands.values.expand((d) => d).toSet();
