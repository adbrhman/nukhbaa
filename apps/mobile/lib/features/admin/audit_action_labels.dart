/// The admin audit actions in words, in one place (audit L-14): the home's
/// latest actions and the audit log used two maps that disagreed ("إيقاف
/// لاعب" and "تعليق مستخدم" for one action) and each lacked values the
/// other had.
library;

/// The words of every `admin.audit_action` wire token this build knows
/// (`AuditAction.wireValue` in the domain, migrations 0010, 0015, 0023,
/// 0098, 0173, 0176, 0183). The keys are the tokens, so a test can check none is missing.
const Map<String, String> auditActionLabels = <String, String>{
  'user_suspended': 'تعليق لاعب',
  'user_reinstated': 'إعادة تفعيل لاعب',
  'user_renamed': 'تغيير اسم لاعب',
  'participant_ledger_viewed': 'اطّلاع على سجل نقاط لاعب',
  'user_predictions_viewed': 'اطّلاع على توقعات لاعب',
  'fixture_result_recorded': 'تسجيل نتيجة مباراة',
  'fixture_schedule_corrected': 'تعديل موعد مباراة',
  'fixture_hidden': 'إخفاء مباراة',
  'fixture_shown': 'إظهار مباراة',
  'fixture_predictions_viewed': 'اطّلاع على توقعات مباراة',
  'fixture_linked_to_round': 'ربط مباراة بجولة',
  'competition_created': 'إنشاء مسابقة',
  'season_started': 'بدء موسم',
  'round_opened': 'فتح جولة',
  'round_locked': 'إغلاق جولة',
  'round_scored': 'احتساب جولة',
  'round_posted_to_ledger': 'ترحيل جولة إلى سجل النقاط',
  'round_predictions_viewed': 'اطّلاع على توقعات جولة',
  'error_updated': 'تحديث حالة خطأ',
  'team_added': 'إضافة نادٍ إلى القائمة',
  'league_added': 'إضافة دوري إلى القائمة',
  'fixtures_merged': 'دمج نسختين من مباراة',
};

/// The words of [action]; one this build predates reads as a plain admin
/// action.
String auditActionLabel(String action) =>
    auditActionLabels[action] ?? 'إجراء إداري';

/// [auditActionLabel] for the audit log itself, where an unknown action
/// keeps its token: a trail must not hide what it does not understand.
String auditLogActionLabel(String action) =>
    auditActionLabels[action] ?? 'إجراء إداري ($action)';
