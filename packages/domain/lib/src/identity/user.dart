import 'package:domain/src/identity/platform_role.dart';
import 'package:domain/src/identity/user_id.dart';
import 'package:shared/shared.dart';

/// The lifecycle state of a platform [User].
///
/// Kept minimal for the Authentication phase: later phases (Admin, Social) may
/// extend the domain policies that transition between states, but the closed
/// set is fixed here so authorization can reason about it exhaustively.
enum UserStatus {
  /// The user may authenticate and act on the platform.
  active,

  /// The user is suspended by an administrator; authentication may succeed at
  /// the identity provider, but the platform denies privileged action.
  suspended;

  /// Whether a user in this status is permitted to act (beyond inspecting their
  /// own identity). Suspension is enforced by the application, not the token.
  bool get canAct => this == UserStatus.active;
}

/// The canonical, platform-owned identity of a person or machine principal
/// (Database ADR, Section 3: `User` is the Identity aggregate root).
///
/// Credentials are NOT modeled here: password handling is delegated entirely to
/// Supabase Auth (Security ADR, Section 2; Application ADR, Section 2). This
/// entity is the platform's own projection of that identity — the join point
/// between an external auth subject and everything the domain owns about them.
///
/// Pure: no framework, no IO. Value-comparable by [id] plus its mutable-looking
/// fields (the instance itself is immutable; state changes produce new values).
final class User {
  /// Creates a canonical user.
  const User({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
    required this.displayName,
    this.avatarMime,
    this.avatarUpdatedAt,
  });

  /// The platform identity, equal to the Supabase Auth subject UUID.
  final UserId id;

  /// The user's email as known to the identity provider. May be absent for
  /// principals authenticated by other means (e.g. phone-only, service).
  final String? email;

  /// The coarse platform authority (first authorization layer).
  final PlatformRole role;

  /// The lifecycle state governing whether the user may act.
  final UserStatus status;

  /// The platform-owned display name shown across the app instead of the raw
  /// email/id (migration 0015; defaults from the email local-part when not
  /// explicitly chosen). Always non-empty once the row exists.
  final String displayName;

  /// The content type of the user's profile picture, or null when they have
  /// none -- the common case, and the reason this is nullable rather than an
  /// empty string: "no picture" is a state the UI acts on (it draws the
  /// name's initial instead), not a blank value.
  ///
  /// The bytes themselves never reach the domain: an image is payload, not a
  /// fact the domain reasons about. This field and [avatarUpdatedAt] are the
  /// whole of what a User knows about its picture.
  final String? avatarMime;

  /// When the current picture was set, or null when there is none. Travels in
  /// the read URL as a cache-busting token, so a replaced picture is a
  /// different URL and no stale copy survives on a device.
  final DateTime? avatarUpdatedAt;

  /// The maximum length of a [displayName], enforced by [validateDisplayName].
  static const int maxDisplayNameLength = 60;

  /// The maximum size of an avatar upload, in bytes -- mirrors the database
  /// CHECK in migration 0033 so a rejection here and a rejection there always
  /// agree.
  static const int maxAvatarBytes = 512 * 1024;

  /// The content types the platform accepts for a profile picture. Mirrors
  /// the database CHECK in migration 0033.
  static const Set<String> allowedAvatarMimeTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  /// The lowest reportable UTC offset, in minutes (UTC-12:00). Together with
  /// [maxUtcOffsetMinutes] this is the real span of inhabited zones, and it
  /// mirrors the CHECK in migration 0055 so a rejection here and a rejection
  /// in Postgres always agree.
  static const int minUtcOffsetMinutes = -720;

  /// The highest reportable UTC offset, in minutes (UTC+14:00).
  static const int maxUtcOffsetMinutes = 840;

  /// Every inhabited zone is a whole number of quarter-hours from UTC
  /// (Kathmandu is +5:45, Chatham +12:45), so a remainder means a broken
  /// client rather than a place.
  static const int utcOffsetStepMinutes = 15;

  /// Validates a raw, untrusted offset from UTC in minutes, as reported by a
  /// client device (`UpdateTimeZoneOffset` use-case).
  ///
  /// An offset is not a time zone: it carries no daylight-saving rule, which
  /// is why the client re-reports it on every start rather than the platform
  /// storing it once. Nothing about a day boundary follows from it -- the
  /// challenge and the streak run on the Riyadh day.
  static Result<int> validateUtcOffsetMinutes(int raw) {
    if (raw < minUtcOffsetMinutes || raw > maxUtcOffsetMinutes) {
      return const Result.err(
        AppError.validation(
          'identity.utc_offset_out_of_range',
          'فرق التوقيت خارج المدى المسموح',
        ),
      );
    }
    if (raw % utcOffsetStepMinutes != 0) {
      return const Result.err(
        AppError.validation(
          'identity.utc_offset_not_quarter_hour',
          'فرق التوقيت يجب أن يكون من مضاعفات ربع الساعة',
        ),
      );
    }
    return Result.ok(raw);
  }

  /// The name the database assigns when none was chosen (migration 0016's
  /// `identity.default_display_name` trigger): the email's local part, or
  /// `Player` for an account without an email.
  String get automaticDisplayName {
    final String local = (email ?? '').split('@').first;
    return local.isEmpty ? 'Player' : local;
  }

  /// Whether this account still carries [automaticDisplayName], i.e. never
  /// chose a display name (a first Google sign-in skips registration).
  bool get hasAutomaticDisplayName => displayName == automaticDisplayName;

  /// Validates a raw, untrusted display name: trims it, rejects empty/too-long
  /// input. Shared by registration (initial name) and [renameDisplayName]
  /// (later changes) so both paths enforce the same invariant.
  static Result<String> validateDisplayName(String raw) {
    final trimmed = raw.replaceAll(_invisible, '').trim();
    if (trimmed.isEmpty) {
      return const Result.err(
        AppError.validation('identity.display_name_empty', 'الاسم مطلوب'),
      );
    }
    if (trimmed.length > maxDisplayNameLength) {
      return const Result.err(
        AppError.validation(
          'identity.display_name_too_long',
          'الاسم طويل جدًا (الحد الأقصى $maxDisplayNameLength حرفًا)',
        ),
      );
    }
    if (isReservedDisplayName(trimmed)) {
      return const Result.err(
        AppError.validation(
          'identity.display_name_reserved',
          'هذا الاسم محجوز لحسابات نُخبة الرسمية. اختر اسماً آخر.',
        ),
      );
    }
    return Result.ok(trimmed);
  }

  /// The refusal of a single name for a new account ([isTwoPartName]).
  static const AppError notTwoPartName = AppError.validation(
    'identity.display_name_not_two_part',
    'اكتب اسمك الأول واسم أبيك أو لقبك، مثل: محمد طاهر أو محمد العماري',
  );

  /// The refusal of a name that starts with a surname ("المغربي الرفاعي").
  static const AppError surnameFirstName = AppError.validation(
    'identity.display_name_surname_first',
    'ابدأ باسمك الأول ثم اسم أبيك أو لقبك، مثل: محمد العماري. '
        'لا يُقبل اللقب وحده',
  );

  /// The refusal of an alias ("ملك الجمال", "ساهر الليل").
  static const AppError aliasName = AppError.validation(
    'identity.display_name_alias',
    'اكتب اسمك الحقيقي لا اسماً مستعاراً، مثل: محمد العماري',
  );

  /// Validates the name a new account chooses: every [validateDisplayName]
  /// rule, then the real-name rules of [newAccountNameError] (asked by the
  /// backup admin 2026-11-02, refined by the owner 2026-11-03).
  /// Registration uses it, and `UpdateDisplayName` (the one choice of a
  /// first Google sign-in) checks the same rules; an admin rename and the
  /// names already chosen are not touched.
  static Result<String> validateNewAccountName(String raw) {
    final Result<String> validated = validateDisplayName(raw);
    if (validated case Ok<String>(:final String value)) {
      final AppError? refused = newAccountNameError(value);
      if (refused != null) {
        return Result.err(refused);
      }
    }
    return validated;
  }

  /// Why [name] is not a new account's real name, or null when it is. In
  /// order: an alias -- a digit, or a word players use as a title
  /// ([_aliasWords]) -- is [aliasName]; a name that starts with a surname
  /// (a first word with the article, unless it is a given name such as
  /// "الحسن") is [surnameFirstName]; fewer than two parts is
  /// [notTwoPartName]. Diacritics, tatweel and hamza forms do not count.
  static AppError? newAccountNameError(String name) {
    final List<String> keys = _wordKeys(name);
    if (RegExp(r'\p{Nd}', unicode: true).hasMatch(name) ||
        keys.any(_aliasWords.contains)) {
      return aliasName;
    }
    if (keys.isNotEmpty &&
        keys.first.startsWith('ال') &&
        !_givenNamesWithArticle.contains(keys.first)) {
      return surnameFirstName;
    }
    if (!isTwoPartName(name)) {
      return notTwoPartName;
    }
    return null;
  }

  /// Whether [name] holds two parts: a first name and a father's name or a
  /// surname, each of two letters or more. "عبد", "أبو" and "أم" join the
  /// next word into one name ("عبد الرحمن" is one name), and the particles
  /// "بن", "ابن", "بنت" and "آل" are not a part ("محمد بن" is one name).
  static bool isTwoPartName(String name) {
    int parts = 0;
    bool joinNext = false;
    for (final String key in _wordKeys(name)) {
      if (key.length < 2 || _particles.contains(key)) {
        continue;
      }
      if (joinNext) {
        joinNext = false;
        continue;
      }
      parts++;
      joinNext = _compoundPrefixes.contains(key);
    }
    return parts >= 2;
  }

  /// Each word of [name] through [_nameKey], letters only.
  static List<String> _wordKeys(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .map(
        (String word) =>
            _nameKey(word).replaceAll(RegExp(r'\p{N}', unicode: true), ''),
      )
      .where((String key) => key.isNotEmpty)
      .toList();

  /// Words that make one name with the word after them.
  static const Set<String> _compoundPrefixes = <String>{'عبد', 'ابو', 'ام'};

  /// Words that are not a part of a name on their own.
  static const Set<String> _particles = <String>{'بن', 'ابن', 'بنت', 'ال'};

  /// Given names that carry the article, so may come first.
  static const Set<String> _givenNamesWithArticle = <String>{
    'الحسن',
    'الحسين',
    'العباس',
    'الخضر',
    'الهادي',
    'المهدي',
    'الطيب',
    'المختار',
    'الامين',
    'الفاتح',
    'المعتصم',
    'الوليد',
    'الصادق',
    'المنصور',
    'الحارث',
    'البراء',
    'الزبير',
    'الفضل',
    'المقداد',
    'المثني',
    'النعمان',
    'الحكم',
  };

  /// Words of the aliases players chose (the titles flagged in the new
  /// players' list, script 202, and the owner's examples), through
  /// [_nameKey]. Kept to words that are never a given name or a surname,
  /// so a real name is not refused; what slips through is renamed by an
  /// admin.
  static const Set<String> _aliasWords = <String>{
    'ملك',
    'الملك',
    'ملكه',
    'الملكه',
    'بطل',
    'البطل',
    'زعيم',
    'الزعيم',
    'قناص',
    'القناص',
    'اسطوره',
    'الاسطوره',
    'عاشق',
    'العاشق',
    'عاشقه',
    'مايسترو',
    'المايسترو',
    'عقيد',
    'العقيد',
    'دكتور',
    'الدكتور',
    'كابتن',
    'الكابتن',
    'امبراطور',
    'الامبراطور',
    'هداف',
    'الهداف',
    'محترف',
    'المحترف',
    'متوقع',
    'المتوقع',
    'جوكر',
    'الجوكر',
    'شبح',
    'الشبح',
    'التوقع',
    'التوقعات',
    'توقعات',
    'الليل',
    'الحب',
    'القلب',
    'الاحساس',
    'الشوق',
    'الغلا',
    'الحزن',
    'الصمت',
    'الظلام',
    'القمر',
    'النجوم',
    'الكوره',
    'الكره',
    'king',
    'legend',
    'captain',
    'boss',
    'joker',
    'sniper',
    'doctor',
    'dr',
  };

  /// Characters a name never keeps: controls, the bidirectional overrides
  /// and isolates, the Arabic letter mark and the invisible spaces. They let
  /// a name pass for another or look empty; the zero-width joiner (U+200D)
  /// stays, for emoji. Removed before the name is checked and stored.
  static final RegExp _invisible = RegExp(
    '[\u0000-\u001F\u007F-\u009F\u061C\u180E\u200B\u200C\u200E'
    '\u200F\u202A-\u202E\u2060-\u2064\u2066-\u2069\uFEFF]',
  );

  /// The names of Nukhbaa's own accounts, compared through [_nameKey].
  static const Set<String> _reservedNames = <String>{
    'نخبه',
    'دعم',
    'الدعم',
    'nukhba',
    'nukhbaa',
    'support',
    'admin',
  };

  /// Words that, beside the brand, make a name read as an official account.
  static const List<String> _officialWords = <String>[
    'دعم',
    'اداره',
    'مشرف',
    'رسمي',
    'support',
    'admin',
    'official',
  ];

  /// Whether [name] would pass for one of Nukhbaa's own accounts (decided
  /// 2026-11-01, review M-4): the brand alone, "support" or "admin" alone,
  /// or the brand with an official word ("دعم نُخبة", "Nukhbaa Support").
  /// Diacritics, tatweel, hamza forms, spaces and punctuation do not count.
  static bool isReservedDisplayName(String name) {
    final String key = _nameKey(name);
    if (_reservedNames.contains(key)) {
      return true;
    }
    final bool brand = key.contains('نخبه') || key.contains('nukhba');
    return brand && _officialWords.any(key.contains);
  }

  static String _nameKey(String name) => name
      .toLowerCase()
      .replaceAll(RegExp('[\u064B-\u0652\u0670\u0640]'), '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// Validates a candidate avatar upload before it reaches
  /// [UserDirectory.setAvatar]: rejects an empty payload, one over
  /// [maxAvatarBytes], or a [mime] outside [allowedAvatarMimeTypes]. The
  /// server checks this before the bytes ever reach the directory; the
  /// database CHECK from migration 0033 is the backstop behind it, not the
  /// first line of defense.
  static Result<void> validateAvatar(int byteLength, String mime) {
    if (byteLength <= 0) {
      return const Result.err(
        AppError.validation('identity.avatar_empty', 'الصورة فارغة'),
      );
    }
    if (byteLength > maxAvatarBytes) {
      return const Result.err(
        AppError.validation(
          'identity.avatar_too_large',
          'حجم الصورة كبير جدًا (الحد الأقصى 512 كيلوبايت)',
        ),
      );
    }
    if (!allowedAvatarMimeTypes.contains(mime)) {
      return const Result.err(
        AppError.validation(
          'identity.avatar_mime_unsupported',
          'صيغة الصورة غير مدعومة (JPEG أو PNG أو WEBP فقط)',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// Whether this user is currently permitted to perform privileged actions.
  /// A [service] principal is always permitted; human users must be [active].
  bool get canAct => role == PlatformRole.service || status.canAct;

  /// Returns a copy with selected fields replaced. Used by directory upserts to
  /// reconcile provider-sourced fields without mutating the original value.
  ///
  /// [clearAvatar] exists because the avatar fields are nullable: passing
  /// null for them cannot mean "remove the picture" when null already means
  /// "leave it alone". Removal is therefore explicit and unmistakable at the
  /// call site.
  User copyWith({
    String? email,
    PlatformRole? role,
    UserStatus? status,
    String? displayName,
    String? avatarMime,
    DateTime? avatarUpdatedAt,
    bool clearAvatar = false,
  }) {
    return User(
      id: id,
      email: email ?? this.email,
      role: role ?? this.role,
      status: status ?? this.status,
      displayName: displayName ?? this.displayName,
      avatarMime: clearAvatar ? null : (avatarMime ?? this.avatarMime),
      avatarUpdatedAt: clearAvatar
          ? null
          : (avatarUpdatedAt ?? this.avatarUpdatedAt),
    );
  }

  /// Changes this user's [displayName] to a validated [name] — the user-driven
  /// counterpart to the auto-derived default from migration 0015. Mirrors
  /// `Group.rename`: validation lives on the aggregate, authority (the caller
  /// may only rename themselves) is enforced by the use-case
  /// (`UpdateDisplayName`), not here.
  Result<User> renameDisplayName(String name) {
    final validated = User.validateDisplayName(name);
    if (validated is Err<String>) {
      return Result.err(validated.error);
    }
    return Result.ok(copyWith(displayName: (validated as Ok<String>).value));
  }

  /// Transitions this user into [UserStatus.suspended] — the reversible
  /// administrator sanction (Admin Panel decision OPEN-A #1: a simple
  /// `suspend`/`reinstate` pair, no temporary-vs-permanent distinction in v1).
  ///
  /// Pure and total: the aggregate reasons only about its own state — the
  /// *authority* to suspend (caller must be a platform admin) and the mandatory
  /// audit reason are enforced by the use-case (`SuspendUser`), not the entity,
  /// mirroring how owner-authority for `Group.rename` lives in the use-case.
  ///
  /// A [service] principal is never a human account and cannot be suspended
  /// (it would silently break internal calls); suspending a `service` user is
  /// refused as an invariant violation. Suspending an already-suspended user is
  /// **idempotent** — it returns an equal value rather than an error, so a
  /// retried sanction converges (mirror of `Notification.markRead`).
  Result<User> suspend() {
    if (role == PlatformRole.service) {
      return const Result.err(
        AppError.invariant(
          'identity.cannot_suspend_service',
          'A service principal cannot be suspended',
        ),
      );
    }
    if (status == UserStatus.suspended) {
      return Result.ok(this);
    }
    return Result.ok(copyWith(status: UserStatus.suspended));
  }

  /// Transitions this user back into [UserStatus.active] — reversing a
  /// suspension (Admin Panel decision OPEN-A #1). The mirror of [suspend]:
  /// pure/total, authority + audit reason enforced in the use-case
  /// (`ReinstateUser`), idempotent when the user is already active.
  Result<User> reinstate() {
    if (status == UserStatus.active) {
      return Result.ok(this);
    }
    return Result.ok(copyWith(status: UserStatus.active));
  }

  @override
  bool operator ==(Object other) =>
      other is User &&
      other.id == id &&
      other.email == email &&
      other.role == role &&
      other.status == status &&
      other.displayName == displayName &&
      other.avatarMime == avatarMime &&
      other.avatarUpdatedAt == avatarUpdatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    email,
    role,
    status,
    displayName,
    avatarMime,
    avatarUpdatedAt,
  );

  @override
  String toString() =>
      'User(${id.value}, role: ${role.name}, '
      'status: ${status.name})';
}
