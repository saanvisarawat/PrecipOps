import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/models/chat_models.dart';

/// The Ragbot screen's EN/ML choice, held at the app's root
/// `ProviderScope` (not screen-local `State`) so it survives navigating
/// away from and back to the chat screen for the lifetime of the app
/// session — reopening the chat doesn't reset it to English.
final chatLanguageProvider = StateProvider<ChatLanguage>((ref) => ChatLanguage.english);
