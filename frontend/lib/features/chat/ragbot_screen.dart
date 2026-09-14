import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../api/models/chat_models.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/api_provider.dart';
import '../../providers/chat_language_provider.dart';
import '../../widgets/status_badge.dart';

/// Malayalam Unicode block (U+0D00–U+0D7F) — Inter (this app's body font)
/// has no glyphs for it, so text containing it needs a script that does or
/// it silently renders as tofu boxes. Applied per-message rather than
/// globally so English messages keep the app's normal type.
final _malayalamPattern = RegExp(r'[ഀ-ൿ]');

TextStyle _localizedBody(String text, {Color? color}) {
  final base = AppTypography.body(color: color ?? AppColors.textPrimary);
  if (!_malayalamPattern.hasMatch(text)) return base;
  final malayalam = GoogleFonts.notoSansMalayalam();
  return base.copyWith(fontFamily: malayalam.fontFamily, fontFamilyFallback: [malayalam.fontFamily!, 'Inter']);
}

const _suggestedQuestions = [
  'What do I do if trapped by rising water?',
  'Where is the nearest shelter?',
  'My laptop got wet — is it safe to charge?',
  'What should I pack before evacuating?',
];

class RagbotScreen extends ConsumerStatefulWidget {
  const RagbotScreen({super.key});

  @override
  ConsumerState<RagbotScreen> createState() => _RagbotScreenState();
}

class _RagbotScreenState extends ConsumerState<RagbotScreen> {
  final _sessionId = const Uuid().v4();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [
    ChatMessage(
      id: 'welcome',
      text: 'Hi, I\'m Ragbot — your flood survival assistant. Ask me about evacuation, '
          'first aid, or what to do right now during flooding.',
      isUser: false,
      mode: ChatMode.online,
      timestamp: DateTime.now(),
    ),
  ];
  bool _isSending = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;
    _textController.clear();
    setState(() {
      _messages.add(ChatMessage(
        id: const Uuid().v4(),
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _isSending = true;
    });
    _scrollToBottom();

    final api = ref.read(preciopsApiProvider);
    final language = ref.read(chatLanguageProvider);
    ChatResponse? response;
    String? errorText;
    try {
      response = await api.sendChatMessage(ChatRequest(message: text, sessionId: _sessionId, language: language));
    } catch (_) {
      // /api/chat is a no-login citizen feature — a failure here is a
      // network/server issue, not an auth gate. Fail into a bot message
      // instead of leaving the typing indicator spinning forever with no
      // way out.
      errorText = "I couldn't reach the survival assistant just now — check your connection and try again.";
    }

    if (!mounted) return;
    setState(() {
      _messages.add(ChatMessage(
        id: const Uuid().v4(),
        text: response?.reply ?? errorText!,
        isUser: false,
        mode: response?.mode,
        timestamp: DateTime.now(),
      ));
      _isSending = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: AppMotion.standard,
          curve: AppMotion.curve,
        );
      }
    });
  }

  ChatMode? get _lastKnownMode {
    for (final m in _messages.reversed) {
      if (!m.isUser && m.mode != null) return m.mode;
    }
    return null;
  }

  void _askSuggested(String question) {
    _textController.text = question;
    _send();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _lastKnownMode;
    final language = ref.watch(chatLanguageProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: Row(
            children: [
              StatusBadge(
                label: mode == null
                    ? 'Ready'
                    : mode == ChatMode.online
                        ? 'Online Knowledge'
                        : 'Offline Knowledge',
                color: mode == ChatMode.offline ? AppColors.warning : AppColors.accent,
                icon: mode == ChatMode.offline ? Icons.wifi_off_rounded : Icons.cloud_done_outlined,
                dot: true,
              ),
              const Spacer(),
              _LanguageToggle(
                value: language,
                onChanged: (v) => ref.read(chatLanguageProvider.notifier).state = v,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
            itemCount: _suggestedQuestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _SuggestionPill(
              label: _suggestedQuestions[i],
              onTap: _isSending ? null : () => _askSuggested(_suggestedQuestions[i]),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: _messages.length + (_isSending ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _messages.length) {
                return const _TypingIndicator();
              }
              return _ChatBubble(message: _messages[i]);
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.compact, AppSpacing.sm, AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _MicButton(onTap: () => context.push('/voice-agent')),
                const SizedBox(width: AppSpacing.compact),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: AppTypography.body(),
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(hintText: 'Ask about flood survival…'),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: AppSpacing.compact),
                _SendButton(enabled: !_isSending, onTap: _send),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _SendButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: AppColors.accent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          splashColor: Colors.black.withValues(alpha: 0.1),
          child: const SizedBox(
            width: 50,
            height: 50,
            child: Icon(Icons.arrow_upward_rounded, color: Colors.black, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Deliberately not a WhatsApp-style two-tone bubble stream: a user
/// question reads as a compact right-aligned tag (it's a query, not a
/// message), and the assistant's answer reads as a plain left-aligned
/// paragraph block — no fill, no border — with a small "Ragbot" label and
/// (when known) the online/offline knowledge-source badge above it.
class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(message.text, style: _localizedBody(message.text)),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.shield_moon_outlined, size: 15, color: AppColors.accent),
                const SizedBox(width: 6),
                Text('Ragbot', style: AppTypography.label().copyWith(fontWeight: FontWeight.w600)),
                if (message.mode != null) ...[
                  const SizedBox(width: 8),
                  StatusBadge(
                    label: message.mode == ChatMode.online ? 'Cloud Verified' : 'Offline Protocol Mode',
                    color: message.mode == ChatMode.online ? AppColors.accent : AppColors.warning,
                    icon: message.mode == ChatMode.online ? Icons.cloud_done : Icons.wifi_off,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(message.text, style: _localizedBody(message.text)),
          ],
        ),
      ),
    );
  }
}

/// Two-state EN/ML segmented pill — same visual language as
/// [PredictorDashboardScreen]'s scenario toggle, scaled down for the chat
/// header. Sending `language` on every request is Ragbot's job; this only
/// owns the on-screen selector.
class _LanguageToggle extends StatelessWidget {
  final ChatLanguage value;
  final ValueChanged<ChatLanguage> onChanged;
  const _LanguageToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('EN', value == ChatLanguage.english, () => onChanged(ChatLanguage.english)),
          _seg('ML', value == ChatLanguage.malayalam, () => onChanged(ChatLanguage.malayalam)),
        ],
      ),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        width: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: AppTypography.caption(color: selected ? Colors.black : AppColors.textSecondary)
              .copyWith(fontWeight: FontWeight.w700, fontSize: 11.5),
        ),
      ),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SuggestionPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.cardBorderSubtle),
            ),
            child: Text(label, style: AppTypography.label()),
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MicButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceRaised,
      shape: const CircleBorder(side: BorderSide(color: AppColors.cardBorder)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 50,
          height: 50,
          child: Icon(Icons.mic_none_rounded, color: AppColors.info, size: 22),
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.surfaceRaised,
          border: Border.all(color: AppColors.cardBorder),
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final t = ((_controller.value - i * 0.2) % 1.0 + 1.0) % 1.0;
                final scale = 0.6 + (t < 0.5 ? t : 1 - t);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
