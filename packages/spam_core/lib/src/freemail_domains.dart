/// Known freemail domains where sender domain reputation should not be shared.
const Set<String> freemailDomains = {
  'gmail.com',
  'googlemail.com',
  'yahoo.com',
  'yahoo.co.uk',
  'yahoo.fr',
  'yahoo.de',
  'yahoo.es',
  'yahoo.it',
  'yahoo.co.jp',
  'ymail.com',
  'rocketmail.com',
  'hotmail.com',
  'hotmail.co.uk',
  'hotmail.fr',
  'hotmail.de',
  'hotmail.it',
  'hotmail.es',
  'outlook.com',
  'outlook.fr',
  'outlook.de',
  'live.com',
  'live.co.uk',
  'live.fr',
  'live.de',
  'msn.com',
  'icloud.com',
  'me.com',
  'mac.com',
  'aol.com',
  'aim.com',
  'proton.me',
  'protonmail.com',
  'zoho.com',
  'zohomail.com',
  'gmx.com',
  'gmx.net',
  'gmx.de',
  'web.de',
  'mail.com',
  'email.com',
  'usa.com',
  'post.com',
  'yandex.ru',
  'yandex.com',
  'ya.ru',
  'tutanota.com',
  'tuta.com',
  'tuta.io',
  'fastmail.com',
  'fastmail.fm',
  'hey.com',
  'inbox.com',
  'naver.com',
  'daum.net',
  'hanmail.net',
  'qq.com',
  '163.com',
  '126.com',
  'sina.com',
};

/// Known disposable email providers.
const Set<String> disposableDomains = {
  'mailinator.com',
  'tempmail.com',
  '10minutemail.com',
  'guerrillamail.com',
  'throwawaymail.com',
  'temp-mail.org',
  'getairmail.com',
  'fakemailgenerator.com',
  'dispostable.com',
  'yopmail.com',
  'sharklasers.com',
  'trashmail.com',
};

/// Checks if a domain is a known freemail provider.
bool isFreemailDomain(String? domain) {
  if (domain == null) return false;
  return freemailDomains.contains(domain.toLowerCase().trim());
}

/// Checks if a domain is a known disposable provider.
bool isDisposableDomain(String? domain) {
  if (domain == null) return false;
  return disposableDomains.contains(domain.toLowerCase().trim());
}
