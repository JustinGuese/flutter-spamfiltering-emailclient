/// Hosted community backend. Override at build time with
/// `--dart-define=BACKEND_URL=https://...` to point the client at your own server.
/// Defined once so the authenticated client and the anonymous community client
/// can never disagree.
const String backendUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'https://emailprogram-spamfilter-backend-api.datafortress.cloud',
);
