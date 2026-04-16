import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api/api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'dart:convert';
import 'package:path/path.dart' as path;

/// ويدجت المرفقات — رفع صور/ملفات وعرضها
class TaskAttachmentsWidget extends StatefulWidget {
  final String taskId;
  final bool readOnly;

  const TaskAttachmentsWidget({
    super.key,
    required this.taskId,
    this.readOnly = false,
  });

  @override
  State<TaskAttachmentsWidget> createState() => _TaskAttachmentsWidgetState();
}

class _TaskAttachmentsWidgetState extends State<TaskAttachmentsWidget> {
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = true;
  bool _isUploading = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  http.Client _createClient() {
    final httpClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true;
    return IOClient(httpClient);
  }

  Future<void> _loadAttachments() async {
    setState(() => _isLoading = true);
    try {
      final apiClient = ApiClient.instance;
      final token = apiClient.authToken;
      if (token == null) return;

      final client = _createClient();
      try {
        final response = await client.get(
          Uri.parse('https://72.61.183.61/api/servicerequests/${widget.taskId}/attachments'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        );

        if (response.statusCode == 200 && mounted) {
          final data = json.decode(response.body);
          final items = data is List ? data : (data['items'] ?? data['data'] ?? []);
          setState(() {
            _attachments = List<Map<String, dynamic>>.from(items);
          });
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // API قد لا يدعم المرفقات بعد — نعرض قائمة فارغة
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked == null) return;
      await _uploadFile(File(picked.path), picked.name);
    } catch (e) {
      _showError('فشل اختيار الصورة');
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'xlsx'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      await _uploadFile(file, result.files.single.name);
    } catch (e) {
      _showError('فشل اختيار الملف');
    }
  }

  Future<void> _uploadFile(File file, String fileName) async {
    setState(() => _isUploading = true);

    try {
      final apiClient = ApiClient.instance;
      final token = apiClient.authToken;
      if (token == null) throw 'غير مصادق';

      final uri = Uri.parse('https://72.61.183.61/api/servicerequests/${widget.taskId}/attachments');

      final httpClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) => true;
      final client = IOClient(httpClient);

      try {
        final request = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(await http.MultipartFile.fromPath('file', file.path, filename: fileName));

        final response = await client.send(request);
        final body = await response.stream.bytesToString();

        if (mounted) {
          if (response.statusCode == 200 || response.statusCode == 201) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('تم رفع المرفق بنجاح'), backgroundColor: Colors.green),
            );
            await _loadAttachments();
          } else {
            debugPrint('Upload failed: status=${response.statusCode}, body=$body, taskId=${widget.taskId}');
            _showError('فشل رفع الملف (${response.statusCode})');
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (mounted) _showError('خطأ في رفع الملف: $e');
      debugPrint('Upload error for taskId=${widget.taskId}: $e');
    }

    if (mounted) setState(() => _isUploading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showUploadOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('إضافة مرفق', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.camera_alt, color: Colors.blue),
                ),
                title: const Text('التقاط صورة'),
                subtitle: const Text('فتح الكاميرا'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.photo_library, color: Colors.green),
                ),
                title: const Text('اختيار من المعرض'),
                subtitle: const Text('صورة من الجهاز'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.attach_file, color: Colors.orange),
                ),
                title: const Text('اختيار ملف'),
                subtitle: const Text('PDF, Word, Excel, صور'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndUploadFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.12)),
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
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Icon(Icons.attach_file_rounded, size: 14, color: Colors.purple),
              ),
              const SizedBox(width: 6),
              const Text('المرفقات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.purple)),
              const Spacer(),
              if (_attachments.isNotEmpty)
                Text('${_attachments.length}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              if (!widget.readOnly) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _isUploading ? null : _showUploadOptions,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.purple,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _isUploading
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 14, color: Colors.white),
                              SizedBox(width: 2),
                              Text('إضافة', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // المحتوى
          if (_isLoading)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
          else if (_attachments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('لا توجد مرفقات', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _attachments.map((a) => _buildAttachmentChip(a)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAttachmentChip(Map<String, dynamic> attachment) {
    final fileName = attachment['FileName']?.toString() ?? attachment['fileName']?.toString() ?? 'ملف';
    final fileUrl = attachment['Url']?.toString() ?? attachment['url']?.toString() ?? '';
    final ext = path.extension(fileName).toLowerCase().replaceAll('.', '');
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);

    return GestureDetector(
      onTap: () {
        if (isImage && fileUrl.isNotEmpty) {
          _showImagePreview(fileUrl, fileName);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(ext),
              size: 16,
              color: _getFileColor(ext),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                fileName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePreview(String url, String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(fileName, style: const TextStyle(fontSize: 14)),
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              automaticallyImplyLeading: false,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.6),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()));
                },
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, size: 48, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('فشل تحميل الصورة'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String ext) {
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'doc': case 'docx': return Icons.description;
      case 'xls': case 'xlsx': return Icons.table_chart;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': return Icons.image;
      default: return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String ext) {
    switch (ext) {
      case 'pdf': return Colors.red;
      case 'doc': case 'docx': return Colors.blue;
      case 'xls': case 'xlsx': return Colors.green;
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': return Colors.purple;
      default: return Colors.grey;
    }
  }
}
