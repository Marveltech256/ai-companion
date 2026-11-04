/// Invitations use only interests selected in the approved companion setup.
/// No mood, diagnosis, or activity history is inferred.
(String, String) companionshipInvitation(List<String> interests) {
  return switch (interests.firstOrNull) {
    'Music' => (
      'A little listening break',
      'Would a familiar song feel good right now?',
    ),
    'Art & making' => (
      'A moment to make',
      'Perhaps a few lines on a page, with no need to finish.',
    ),
    'Books' => (
      'A page, at your pace',
      'Would you like to talk about something you have read?',
    ),
    'Cooking' => (
      'Something simple',
      'A familiar recipe, if making something sounds good.',
    ),
    'Little adventures' => (
      'A change of scene',
      'Maybe a short walk, if it suits your day.',
    ),
    _ => (
      'A little space for you.',
      'Would you like company, ideas, or a listening ear?',
    ),
  };
}
