import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:foxcloud/config/fox_config.dart';
import 'package:foxcloud/services/support_service.dart';
import 'package:image_picker/image_picker.dart';

/// Вкладка «Поддержка» — чат с техподдержкой + история обращений.
class SupportChatView extends StatefulWidget {
  const SupportChatView({super.key});

  @override
  State<SupportChatView> createState() => _SupportChatViewState();
}

class _SupportChatViewState extends State<SupportChatView> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _svc = SupportService.instance;
  final _picker = ImagePicker();

  List<SupportMessage> _messages = [];
  List<SupportTicketInfo> _history = [];
  bool _isLoading = true;
  bool _isSending = false;
  Uint8List? _pendingImage;
  Timer? _pollTimer;
  String? _adminAvatarUrl;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _loadAdminAvatar();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminAvatar() async {
    final url = await _svc.getAdminAvatarUrl();
    if (mounted && url != null) setState(() => _adminAvatarUrl = url);
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _svc.getMessages(),
      _svc.getHistory(),
    ]);
    if (mounted) {
      setState(() {
        _messages = results[0] as List<SupportMessage>;
        _history = results[1] as List<SupportTicketInfo>;
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _poll() async {
    if (!mounted) return;
    final allMsgs = await _svc.getMessages();
    if (mounted && allMsgs.isNotEmpty) {
      final hadNew = allMsgs.length > _messages.length;
      setState(() => _messages = allMsgs);
      if (hadNew) _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _pendingImage == null) return;

    setState(() => _isSending = true);
    final ok = await _svc.sendMessage(text: text, imageBytes: _pendingImage);
    if (ok && mounted) {
      _controller.clear();
      setState(() => _pendingImage = null);
      await _poll();
    }
    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() => _pendingImage = bytes);
      }
    } catch (_) {}
  }

  Future<void> _closeTicket() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Закрыть обращение?'),
        content: const Text('Обращение будет закрыто и перемещено в историю.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Закрыть')),
        ],
      ),
    );
    if (confirm == true) {
      await _svc.closeTicket();
      if (mounted) await _loadAll();
    }
  }

  void _openHistory(SupportTicketInfo ticket) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TicketHistoryPage(
          ticketId: ticket.id,
          adminAvatarUrl: _adminAvatarUrl,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasActiveChat = _messages.isNotEmpty;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Если есть активный чат — показываем его
    if (hasActiveChat) {
      return _buildChat(cs);
    }

    // Иначе — экран приветствия + история
    return _buildWelcomeWithHistory(cs);
  }

  Widget _buildWelcomeWithHistory(ColorScheme cs) {
    final closedTickets = _history.where((t) => t.status == 'closed').toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 32),
              Icon(Icons.support_agent, size: 64, color: cs.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                'Напишите нам!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Опишите проблему или задайте вопрос.\nМожно приложить скриншот.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
              ),
              if (closedTickets.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text(
                  'История обращений',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ...closedTickets.map((t) => _HistoryTile(
                  ticket: t,
                  onTap: () => _openHistory(t),
                )),
              ],
            ],
          ),
        ),
        // ── Превью вложения ──
        if (_pendingImage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_pendingImage!, height: 80, width: 80, fit: BoxFit.cover),
                ),
                Positioned(
                  right: -4,
                  top: -4,
                  child: GestureDetector(
                    onTap: () => setState(() => _pendingImage = null),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.error,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14, color: cs.onError),
                    ),
                  ),
                ),
              ],
            ),
          ),
        // ── Поле ввода ──
        _buildInputBar(cs),
      ],
    );
  }

  Widget _buildChat(ColorScheme cs) {
    return Column(
      children: [
        // ── Кнопка закрытия тикета ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Завершить обращение'),
              onPressed: _closeTicket,
              style: FilledButton.styleFrom(
                backgroundColor: cs.error.withValues(alpha: 0.15),
                foregroundColor: cs.error,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),

        // ── Сообщения ──
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _messages.length,
            itemBuilder: (_, i) => _MessageBubble(
              message: _messages[i],
              baseUrl: SupportService.instance.fullImageUrl(''),
              adminAvatarUrl: _adminAvatarUrl,
            ),
          ),
        ),

        // ── Превью вложения ──
        if (_pendingImage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_pendingImage!, height: 80, width: 80, fit: BoxFit.cover),
                ),
                Positioned(
                  right: -4,
                  top: -4,
                  child: GestureDetector(
                    onTap: () => setState(() => _pendingImage = null),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.error,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close, size: 14, color: cs.onError),
                    ),
                  ),
                ),
              ],
            ),
          ),

        // ── Поле ввода ──
        _buildInputBar(cs),
      ],
    );
  }

  Widget _buildInputBar(ColorScheme cs) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3))),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.image),
              onPressed: _isSending ? null : _pickImage,
              tooltip: 'Прикрепить скриншот',
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isSending,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Сообщение...',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            _isSending
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                    tooltip: 'Отправить',
                  ),
          ],
        ),
      ),
    );
  }
}


/// Плитка обращения в истории.
class _HistoryTile extends StatelessWidget {
  final SupportTicketInfo ticket;
  final VoidCallback onTap;

  const _HistoryTile({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Parse date
    String dateStr = '';
    try {
      final dt = DateTime.parse(ticket.createdAt);
      dateStr = '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {}

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '#${ticket.id}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Обращение #${ticket.id}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    if (ticket.firstMessage != null && ticket.firstMessage!.isNotEmpty)
                      Text(
                        ticket.firstMessage!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dateStr,
                    style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${ticket.messageCount} сообщ.',
                      style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}


/// Страница просмотра истории конкретного обращения (read-only).
class _TicketHistoryPage extends StatefulWidget {
  final int ticketId;
  final String? adminAvatarUrl;

  const _TicketHistoryPage({required this.ticketId, this.adminAvatarUrl});

  @override
  State<_TicketHistoryPage> createState() => _TicketHistoryPageState();
}

class _TicketHistoryPageState extends State<_TicketHistoryPage> {
  List<SupportMessage> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final msgs = await SupportService.instance.getTicketMessages(widget.ticketId);
    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Обращение #${widget.ticketId}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _messages.isEmpty
              ? const Center(child: Text('Нет сообщений'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) => _MessageBubble(
                    message: _messages[i],
                    baseUrl: SupportService.instance.fullImageUrl(''),
                    adminAvatarUrl: widget.adminAvatarUrl,
                  ),
                ),
    );
  }
}

/// Пузырь сообщения.
class _MessageBubble extends StatelessWidget {
  final SupportMessage message;
  final String baseUrl;
  final String? adminAvatarUrl;

  const _MessageBubble({required this.message, required this.baseUrl, this.adminAvatarUrl});

  @override
  Widget build(BuildContext context) {
    final isUser = message.sender == 'user';
    final cs = Theme.of(context).colorScheme;

    final bubbleColor = isUser
        ? cs.primaryContainer
        : cs.secondaryContainer;
    final textColor = isUser
        ? cs.onPrimaryContainer
        : cs.onSecondaryContainer;
    final alignment = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final margin = isUser
        ? const EdgeInsets.only(left: 48, bottom: 6)
        : const EdgeInsets.only(left: 0, right: 48, bottom: 6);

    // Parse time
    String timeStr = '';
    try {
      final dt = DateTime.parse(message.createdAt);
      timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    // Checkmark icon
    Widget checkIcon() {
      if (!isUser) return const SizedBox.shrink();
      final checkColor = textColor.withValues(alpha: 0.5);
      if (message.isRead) {
        return Icon(Icons.done_all, size: 14, color: checkColor);
      }
      return Icon(Icons.done, size: 14, color: checkColor);
    }

    return Container(
      margin: margin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: cs.primaryContainer,
                backgroundImage: adminAvatarUrl != null ? NetworkImage(adminAvatarUrl!) : null,
                child: adminAvatarUrl == null
                    ? Text('Ж', style: TextStyle(fontSize: 14, color: cs.primary))
                    : null,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: alignment,
              children: [
                if (!isUser)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text(
                      'Женя',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: GestureDetector(
                        onTap: () => _showFullImage(context, message.imageUrl!),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 180, maxHeight: 140),
                          child: Image.network(
                            _fullUrl(message.imageUrl!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 48),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (message.text != null && message.text!.isNotEmpty)
                  Text(
                    message.text!,
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    ),
                    if (isUser) ...[
                      const SizedBox(width: 3),
                      checkIcon(),
                    ],
                  ],
                ),
              ],
            ),
          ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fullUrl(String url) {
    if (url.startsWith('http')) return url;
    // baseUrl already ends without trailing slash
    final authUrl = FoxConfig.authServerUrl;
    final idx = authUrl.indexOf('/api/');
    final base = idx != -1 ? authUrl.substring(0, idx) : authUrl;
    return '$base$url';
  }

  void _showFullImage(BuildContext context, String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                _fullUrl(imageUrl),
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 64, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
