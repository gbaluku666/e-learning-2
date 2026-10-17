/// Paste the Web App URL you get after deploying backend/Code.gs
/// (Deploy > New deployment > Web app). It looks like:
/// https://script.google.com/macros/s/AKfycb.../exec
const String kApiUrl = 'https://script.google.com/macros/s/AKfycbxA0V9X2RuA5TOM0FVcS7cECs7mdOzGKr3iZ9pNfXxbKoAlVJpQlaLcJ_6qciUOGCGP/exec';

/// A student can only tick a topic as "read" after spending this long on it.
const int kMinReadSeconds = 30;

/// Used for the "you are behind schedule" reminder on the progress page.
const int kSemesterDays = 120;
