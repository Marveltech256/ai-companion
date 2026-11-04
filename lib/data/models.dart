class PersonalProfile {
  const PersonalProfile({
    this.preferredName,
    this.displayName,
    this.timezone,
    this.language,
    this.location,
    this.username,
    this.ageGroup,
    this.introductionCompletedAt,
    this.welcomeCompletedAt,
    this.timezoneAutomatic = false,
    this.replyMode = 'text',
  });
  final String? preferredName, displayName, timezone, language, location;
  final String? username;
  final String? ageGroup, introductionCompletedAt, welcomeCompletedAt;
  final bool timezoneAutomatic;
  final String replyMode;
  factory PersonalProfile.fromJson(Map<String, dynamic> json) =>
      PersonalProfile(
        preferredName: json['preferred_name'] as String?,
        displayName: json['display_name'] as String?,
        timezone: json['timezone'] as String?,
        language: json['language'] as String?,
        location: json['general_location'] as String?,
        username: json['username'] as String?,
        ageGroup: json['age_group'] as String?,
        introductionCompletedAt: json['introduction_completed_at'] as String?,
        welcomeCompletedAt: json['welcome_completed_at'] as String?,
        timezoneAutomatic: json['timezone_automatic'] == true,
        replyMode: json['reply_mode'] as String? ?? 'text',
      );
  Map<String, dynamic> toInput() => {
    'preferred_name': preferredName,
    'display_name': displayName,
    'timezone': timezone,
    'language': language,
    'general_location': location,
    'username': username,
  };
}

class CompanionPreferences {
  const CompanionPreferences({
    this.personalities = const [],
    this.support = const [],
    this.communication,
    this.learning = '',
    this.goals = '',
    this.additional = '',
  });
  final List<String> personalities, support;
  final String? communication;
  final String learning, goals, additional;
  factory CompanionPreferences.fromJson(Map<String, dynamic> json) =>
      CompanionPreferences(
        personalities: List<String>.from(
          json['personality_keys'] as List? ?? [],
        ),
        support: List<String>.from(json['support_preferences'] as List? ?? []),
        communication: json['interaction_style'] as String?,
        learning: json['learning_interests'] as String? ?? '',
        goals: json['personal_goals'] as String? ?? '',
        additional: json['additional_information'] as String? ?? '',
      );
  Map<String, dynamic> toInput() => {
    'personality_keys': personalities,
    'support_preferences': support,
    'interaction_style': communication,
    'learning_interests': learning,
    'personal_goals': goals,
    'additional_information': additional,
  };
}

class Companion {
  const Companion({
    required this.id,
    required this.name,
    required this.style,
    required this.interests,
    required this.responseLength,
    required this.memoryEnabled,
    this.retentionDays,
    this.learningEnabled = false,
    this.voiceEnabled = false,
    this.conversationRetentionDays,
    this.preferences = const CompanionPreferences(),
  });
  final String id, name, style;
  final List<String> interests;
  final double responseLength;
  final bool memoryEnabled;
  final bool learningEnabled;
  final bool voiceEnabled;
  final int? retentionDays;
  final int? conversationRetentionDays;
  final CompanionPreferences preferences;
  factory Companion.fromJson(Map<String, dynamic> json) => Companion(
    id: json['id'] as String,
    name: json['name'] as String,
    style: json['communication_style'] as String,
    interests: List<String>.from(json['interests'] as List),
    responseLength: (json['response_length'] as num).toDouble(),
    memoryEnabled: json['memory_enabled'] as bool,
    retentionDays: json['retention_days'] as int?,
    learningEnabled: json['learning_enabled'] == true,
    voiceEnabled: json['voice_enabled'] == true,
    conversationRetentionDays: json['conversation_retention_days'] as int?,
    preferences: CompanionPreferences.fromJson(json),
  );
  Map<String, dynamic> toInput() => {
    'name': name,
    'style': style,
    'interests': interests,
    'response_length': responseLength,
    'memory_enabled': memoryEnabled,
    'retention_days': retentionDays,
  };
  Companion copyWith({
    String? name,
    String? style,
    List<String>? interests,
    double? responseLength,
    bool? memoryEnabled,
    bool? learningEnabled,
    bool? voiceEnabled,
    int? retentionDays,
    bool clearRetention = false,
    int? conversationRetentionDays,
    bool clearConversationRetention = false,
    CompanionPreferences? preferences,
  }) => Companion(
    id: id,
    name: name ?? this.name,
    style: style ?? this.style,
    interests: interests ?? this.interests,
    responseLength: responseLength ?? this.responseLength,
    memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    learningEnabled: learningEnabled ?? this.learningEnabled,
    voiceEnabled: voiceEnabled ?? this.voiceEnabled,
    retentionDays: clearRetention ? null : retentionDays ?? this.retentionDays,
    conversationRetentionDays: clearConversationRetention
        ? null
        : conversationRetentionDays ?? this.conversationRetentionDays,
    preferences: preferences ?? this.preferences,
  );
}

class NotificationPreferences {
  const NotificationPreferences({
    this.checkins = false,
    this.suggestions = false,
    this.birthdays = false,
    this.timezone,
    this.localMinute = 1140,
    this.weekdays = const [0, 1, 2, 3, 4, 5, 6],
    this.quietStart = 1320,
    this.quietEnd = 480,
    this.additionalMinutes = const [],
    this.maxPerDay = 1,
    this.inactivityDays = 2,
  });
  final bool checkins, suggestions, birthdays;
  final String? timezone;
  final int localMinute, quietStart, quietEnd;
  final List<int> weekdays;
  final List<int> additionalMinutes;
  final int maxPerDay;
  final int inactivityDays;
  bool get enabled => checkins || suggestions || birthdays;
  factory NotificationPreferences.fromJson(Map<String, dynamic> json) =>
      NotificationPreferences(
        checkins: json['checkins_enabled'] == true,
        suggestions: json['suggestions_enabled'] == true,
        birthdays: json['birthdays_enabled'] == true,
        timezone: json['timezone'] as String?,
        localMinute: json['local_minute'] as int,
        quietStart: json['quiet_start'] as int,
        quietEnd: json['quiet_end'] as int,
        weekdays: List<int>.from(json['weekdays'] as List),
        additionalMinutes: List<int>.from(
          json['additional_minutes'] as List? ?? [],
        ),
        maxPerDay: json['max_per_day'] as int? ?? 1,
        inactivityDays: json['inactivity_days'] as int? ?? 0,
      );
  Map<String, dynamic> toInput(String companion) => {
    'companion_id': companion,
    'checkins_enabled': checkins,
    'suggestions_enabled': suggestions,
    'birthdays_enabled': birthdays,
    'timezone': timezone,
    'local_minute': localMinute,
    'weekdays': weekdays,
    'quiet_start': quietStart,
    'quiet_end': quietEnd,
    'additional_minutes': additionalMinutes,
    'max_per_day': maxPerDay,
    'inactivity_days': inactivityDays,
  };
  NotificationPreferences copyWith({
    bool? checkins,
    bool? suggestions,
    bool? birthdays,
  }) => NotificationPreferences(
    checkins: checkins ?? this.checkins,
    suggestions: suggestions ?? this.suggestions,
    birthdays: birthdays ?? this.birthdays,
    timezone: timezone,
    localMinute: localMinute,
    weekdays: weekdays,
    quietStart: quietStart,
    quietEnd: quietEnd,
    additionalMinutes: additionalMinutes,
    maxPerDay: maxPerDay,
    inactivityDays: inactivityDays,
  );
}

class Conversation {
  const Conversation({required this.id, required this.title});
  final String id, title;
  factory Conversation.fromJson(Map<String, dynamic> json) =>
      Conversation(id: json['id'] as String, title: json['title'] as String);
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.pending = false,
    this.failed = false,
    this.requestId,
    this.seq,
    this.turnKind = 'user',
  });
  final String id, role, content;
  final bool pending, failed;
  final String? requestId;
  final int? seq;
  final String turnKind;
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['id'] as String,
    role: json['role'] as String,
    content: json['content'] as String,
    pending: json['status'] == 'pending',
    failed: json['status'] == 'failed',
    requestId: json['request_id'] as String?,
    seq: json['seq'] as int?,
    turnKind: json['kind'] as String? ?? 'user',
  );
}

class CompanionMemory {
  const CompanionMemory({
    required this.id,
    required this.category,
    required this.key,
    required this.title,
    required this.content,
    required this.updatedAt,
    this.expiresAt,
    this.attributes = const {},
    this.verification = 'user_confirmed',
    this.sourceQuote,
    this.sourceMessageId,
    this.createdAt,
    this.confidence,
    this.temporalStatus = 'durable',
  });
  final String id, category, key, title, content;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final Map<String, dynamic> attributes;
  final String verification, temporalStatus;
  final String? sourceQuote, sourceMessageId;
  final DateTime? createdAt;
  final double? confidence;
  factory CompanionMemory.fromJson(Map<String, dynamic> json) =>
      CompanionMemory(
        id: json['id'] as String,
        category: json['category'] as String,
        key: json['memory_key'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        expiresAt: DateTime.tryParse(json['expires_at'] as String? ?? ''),
        attributes: Map<String, dynamic>.from(json['attributes'] as Map? ?? {}),
        verification: json['verification'] as String? ?? 'user_confirmed',
        temporalStatus: json['temporal_status'] as String? ?? 'durable',
        sourceQuote: json['source_quote'] as String?,
        sourceMessageId: json['source_message_id'] as String?,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
        confidence: (json['confidence'] as num?)?.toDouble(),
      );
}
