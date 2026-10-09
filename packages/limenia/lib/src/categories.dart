/// Codes of the default policies Limenia creates for every tenant during
/// onboarding (integration guide of Limenia, https://limenia.eu/docs/integration.md, section 3.3).
///
/// Limenia only checks the pattern of `reasonCategory`, not this list. Tenants
/// can change and add policies, so agree on the codes with the tenant.
abstract final class ReasonCategory {
  static const spam = 'spam';
  static const harassmentHate = 'harassment_hate';
  static const violence = 'violence';
  static const sexualContent = 'sexual_content';
  static const childSafety = 'child_safety';
  static const fraud = 'fraud';
  static const copyright = 'copyright';
  static const privacy = 'privacy';
  static const selfHarm = 'self_harm';
  static const other = 'other';

  /// The default set in the order of the onboarding.
  static const defaults = [
    spam,
    harassmentHate,
    violence,
    sexualContent,
    childSafety,
    fraud,
    copyright,
    privacy,
    selfHarm,
    other,
  ];

  /// Categories for suspected abuse of minors. The case becomes urgent at
  /// once and Limenia never downloads the media, it keeps the URL only.
  static const childSafetyCategories = {childSafety, 'protection_of_minors'};

  static final _pattern = RegExp(r'^[a-z0-9_]{2,40}$');

  /// Whether [code] has the form Limenia accepts.
  static bool isValid(String code) => _pattern.hasMatch(code);
}
