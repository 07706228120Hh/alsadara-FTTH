import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../models/task.dart';
import '../services/task_api_service.dart';
import '../frontend/frontend.dart';

/// تسجيل تشخيصي في وضع التطوير فقط (يمنع تسريب السجلّات في الإصدار).
void _devLog(String message) {
  if (kDebugMode) debugPrint(message);
}

/// قسم تعليقات المهمة — مستخرج من TaskCard كوحدة مستقلة تملك حالتها.
/// يُحمّل تعليقاته عند إنشائه (أي عند توسيع البطاقة)، بسلوك مطابق للسابق.
class TaskCommentsSection extends StatefulWidget {
  /// معرّف المهمة (GUID إن وُجد وإلا id) — نفس ما كانت تمرّره TaskCard.
  final String taskId;

  /// تعليقات محمّلة مسبقاً (كاش الأب) — إن وُجدت لا نُعيد الجلب من الـAPI.
  /// يحافظ على سلوك التخزين المؤقت الأصلي عبر طيّ/توسيع البطاقة.
  final List<Map<String, dynamic>>? initialComments;

  /// يُستدعى عند نجاح التحميل لتحديث كاش الأب (ليبقى بعد تفكيك الودجت).
  final ValueChanged<List<Map<String, dynamic>>>? onCommentsLoaded;

  const TaskCommentsSection({
    super.key,
    required this.taskId,
    this.initialComments,
    this.onCommentsLoaded,
  });

  @override
  State<TaskCommentsSection> createState() => _TaskCommentsSectionState();
}

class _TaskCommentsSectionState extends State<TaskCommentsSection> {
  List<Map<String, dynamic>> _comments = [];
  bool _isLoadingComments = false;
  bool _commentsLoaded = false;
  final TextEditingController _commentController = TextEditingController();
  bool _isSendingComment = false;

  @override
  void initState() {
    super.initState();
    final cached = widget.initialComments;
    if (cached != null) {
      // كاش الأب موجود (توسيع سابق) — نعرضه فوراً بلا جلب، كسلوك الأصل.
      _comments = cached;
      _commentsLoaded = true;
    } else {
      // أول توسيع — نحمّل من الـAPI (القسم لا يُنشأ إلا عند التوسيع فالتوقيت مطابق).
      _loadComments();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    if (_commentsLoaded || _isLoadingComments) return;
    setState(() => _isLoadingComments = true);
    try {
      final result = await TaskApiService.instance.getComments(widget.taskId);
      if (result['success'] == true && mounted) {
        final data = result['data'];
        List items = [];
        if (data is List) {
          items = data;
        } else if (data is Map && data.containsKey('items')) {
          items = data['items'] as List? ?? [];
        }
        setState(() {
          _comments = items.cast<Map<String, dynamic>>();
          _commentsLoaded = true;
        });
        // تحديث كاش الأب ليبقى بعد تفكيك الودجت عند الطيّ.
        widget.onCommentsLoaded?.call(_comments);
      }
    } catch (e) {
      // فشل جلب التعليقات غير حرج — نُبقي القائمة فارغة ونسجّل في التطوير فقط.
      _devLog('⚠️ تعذّر جلب تعليقات المهمة: $e');
    }
    if (mounted) setState(() => _isLoadingComments = false);
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSendingComment = true);
    try {
      final result =
          await TaskApiService.instance.addComment(widget.taskId, content: text);
      if (result['success'] == true && mounted) {
        _commentController.clear();
        _commentsLoaded = false;
        await _loadComments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('تم إضافة التعليق'),
                backgroundColor: SdColors.success,
                duration: Duration(seconds: 2)),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result['message'] ?? 'فشل إضافة التعليق'),
              backgroundColor: SdColors.danger),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('خطأ في إضافة التعليق'),
              backgroundColor: SdColors.danger),
        );
      }
    }
    if (mounted) setState(() => _isSendingComment = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: SdColors.accent.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SdColors.accent.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // عنوان
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: SdColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.comment_outlined,
                    size: 14, color: SdColors.accent),
              ),
              const SizedBox(width: 6),
              const Text('التعليقات',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: SdColors.accent)),
              const Spacer(),
              if (_comments.isNotEmpty)
                Text('${_comments.length}',
                    style: TextStyle(fontSize: 11, color: SdColors.faint)),
            ],
          ),
          const SizedBox(height: 8),

          // قائمة التعليقات
          if (_isLoadingComments)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('لا توجد تعليقات بعد',
                  style: TextStyle(fontSize: 12, color: SdColors.faint)),
            )
          else
            ..._comments.take(5).map((c) => _buildCommentItem(c)),

          if (_comments.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                  child: Text('+ ${_comments.length - 5} تعليقات أخرى',
                      style:
                          TextStyle(fontSize: 11, color: SdColors.faint))),
            ),

          const SizedBox(height: 8),

          // حقل إضافة تعليق
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'أضف تعليقاً...',
                    hintStyle: TextStyle(fontSize: 12, color: SdColors.faint),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: SdColors.edge)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: SdColors.edge)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: const BorderSide(
                            color: SdColors.accent, width: 1.5)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _isSendingComment ? null : _addComment,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isSendingComment ? SdColors.edge : SdColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: _isSendingComment
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded,
                          size: 16, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem(Map<String, dynamic> comment) {
    final content =
        comment['Content']?.toString() ?? comment['content']?.toString() ?? '';
    final author = comment['UserName']?.toString() ??
        comment['userName']?.toString() ??
        comment['CreatedByName']?.toString() ??
        comment['createdBy']?.toString() ??
        '';
    final dateStr = comment['CreatedAt']?.toString() ??
        comment['createdAt']?.toString() ??
        '';
    // UTC → local (comments were shown 3h behind for Baghdad)
    final date = Task.parseServerDate(dateStr);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SdColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline, size: 14, color: SdColors.faint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  author.isNotEmpty ? author : 'مجهول',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: SdColors.muted),
                ),
              ),
              if (date != null)
                Text(
                  DateFormat('MM/dd HH:mm').format(date),
                  style: TextStyle(fontSize: 11, color: SdColors.faint),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(content,
              style: const TextStyle(
                  fontSize: 12, color: SdColors.ink, height: 1.4)),
        ],
      ),
    );
  }
}
