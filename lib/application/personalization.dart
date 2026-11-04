/// Explicit supported introduction choices. Other stored language preferences
/// remain intact; no language, timezone or age is inferred from a person's name.
const conversationLanguages = {
  'en': 'English',
  'sw': 'Kiswahili',
  'fr': 'Français',
  'es': 'Español',
  'pt': 'Português',
  'ar': 'العربية',
};
const ageGroups = {
  '18_24': '18–24',
  '25_34': '25–34',
  '35_44': '35–44',
  '45_54': '45–54',
  '55_plus': '55+',
};

String languageCode(String? value) {
  if (conversationLanguages.containsKey(value)) return value!;
  return switch ((value ?? '').toLowerCase()) {
    'french' => 'fr',
    'swahili' || 'kiswahili' => 'sw',
    'spanish' => 'es',
    'portuguese' => 'pt',
    'arabic' => 'ar',
    _ => 'en',
  };
}

String storedLanguageChoice(String? value) {
  if (value == null || value.trim().isEmpty) return 'en';
  final code = languageCode(value);
  if (code != 'en' || ['en', 'english'].contains(value.toLowerCase())) {
    return code;
  }
  return value;
}

String welcomeTitle(String name, String? language) =>
    switch (languageCode(language)) {
      'sw' => 'Nimefurahi kukutana nawe, $name!',
      'fr' => 'Ravi de te rencontrer, $name !',
      'es' => '¡Un gusto conocerte, $name!',
      'pt' => 'Prazer em conhecer você, $name!',
      'ar' => 'سعدت بلقائك، $name!',
      _ => 'Nice to meet you, $name!',
    };

String homeGreeting(
  String? name,
  String? language,
  DateTime? local,
  DateTime? last,
  DateTime now,
) {
  final returning =
      last != null && now.toUtc().difference(last.toUtc()).inHours >= 24;
  final person = name == null || name.isEmpty ? '' : ', $name';
  final code = languageCode(language);
  if (returning) {
    return switch (code) {
      'sw' => 'Karibu tena$person.',
      'fr' => 'Bon retour$person.',
      'es' => 'Qué bueno verte de nuevo$person.',
      'pt' => 'Que bom ver você de novo$person.',
      'ar' => 'أهلًا بعودتك${name == null ? '' : '، $name'}.',
      _ => 'Welcome back$person.',
    };
  }
  // Only the server's verified profile timezone establishes a local hour.
  if (local == null) {
    return switch (code) {
      'sw' => 'Habari$person.',
      'fr' => 'Salut$person.',
      'es' => 'Hola$person.',
      'pt' => 'Olá$person.',
      'ar' => 'مرحبًا${name == null ? '' : '، $name'}.',
      _ => 'Hi$person.',
    };
  }
  final morning = local.hour < 12, evening = local.hour >= 18;
  return switch (code) {
    'sw' =>
      '${morning
          ? 'Habari za asubuhi'
          : evening
          ? 'Habari za jioni'
          : 'Habari za mchana'}$person.',
    'fr' => '${evening ? 'Bonsoir' : 'Bonjour'}$person.',
    'es' =>
      '${morning
          ? 'Buenos días'
          : evening
          ? 'Buenas noches'
          : 'Buenas tardes'}$person.',
    'pt' =>
      '${morning
          ? 'Bom dia'
          : evening
          ? 'Boa noite'
          : 'Boa tarde'}$person.',
    'ar' =>
      '${morning ? 'صباح الخير' : 'مساء الخير'}${name == null ? '' : '، $name'}.',
    _ =>
      '${morning
          ? 'Good morning'
          : evening
          ? 'Good evening'
          : 'Good afternoon'}$person.',
  };
}
