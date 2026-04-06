/// اسم الصفحة: ملفات جوجل درايف
/// وصف الصفحة: صفحة إدارة ملفات جوجل درايف
/// المؤلف: تطبيق السدارة
/// تاريخ الإنشاء: 2024
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../config/app_secrets.dart';

class GoogleDriveFilesPage extends StatefulWidget {
  const GoogleDriveFilesPage({super.key});

  @override
  State<GoogleDriveFilesPage> createState() => _GoogleDriveFilesPageState();
}

class _GoogleDriveFilesPageState extends State<GoogleDriveFilesPage> {
  final String folderId =
      '1HWckEov1vjxyRZcCVpUX8YzJJCyWRsQP'; // معرف المجلد الرئيسي
  // 🔒 تم نقل المفتاح إلى AppSecrets
  String get apiKey => appSecrets.googleDriveApiKey;

  String searchQuery = '';
  List<Map<String, String>> allFiles = [];
  List<Map<String, String>> filteredFiles = [];
  bool isLoading = true; // حالة التحميل
  int totalFilesCount = 0; // العدد الإجمالي للملفات

  @override
  void initState() {
    super.initState();
    fetchAllFiles(folderId, 'المنطقة الرئيسية');
  }

  /// جلب جميع الملفات من Google Drive
  Future<void> fetchAllFiles(String parentId, String parentRegion) async {
    try {
      setState(() {
        isLoading = true;
      });

      final url =
          'https://www.googleapis.com/drive/v3/files?q=\'$parentId\'+in+parents&key=$apiKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        int folderFileCount = 0;

        for (var file in data['files']) {
          if (file['mimeType'] == 'application/vnd.google-apps.folder') {
            // جلب الملفات من المجلدات الفرعية
            await fetchAllFiles(file['id'], file['name']);
          } else {
            folderFileCount++;
            setState(() {
              allFiles.add({
                "name": file['name'],
                "region": parentRegion,
                "url":
                    'https://drive.google.com/uc?id=${file['id']}&export=download',
              });
            });
          }
        }

        // تحديث العدد الإجمالي للملفات
        setState(() {
          totalFilesCount += folderFileCount;
          filteredFiles = allFiles;
        });
      } else {
        throw Exception('فشل في جلب الملفات من Google Drive');
      }
    } catch (e) {
      _showErrorDialog('خطأ أثناء جلب الملفات');
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  /// فتح ملف KML باستخدام مكتبة OpenFile
  Future<void> openInGoogleEarth(String? url, String name) async {
    if (url == null || url.isEmpty) {
      _showErrorDialog('الرابط غير متوفر.');
      return;
    }

    try {
      // الحصول على مسار التخزين الخاص بالتطبيق
      final directory = await getApplicationDocumentsDirectory();
      final appFolder = Directory('${directory.path}/GoogleDriveFiles');

      // إنشاء المجلد إذا لم يكن موجودًا
      if (!await appFolder.exists()) {
        await appFolder.create();
      }

      final filePath = '${appFolder.path}/$name';
      final file = File(filePath);

      // تنزيل الملف إذا لم يكن موجودًا
      if (!await file.exists()) {
        final response = await http.get(Uri.parse(url));
        await file.writeAsBytes(response.bodyBytes);
      }

      // فتح الملف باستخدام مكتبة OpenFile
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        _showErrorDialog('تعذر فتح الملف. تحقق من تثبيت Google Earth.');
      }
    } catch (e) {
      _showErrorDialog('تعذر فتح الرابط');
    }
  }

  /// عرض رسالة خطأ
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// تحديث نتائج البحث
  void updateSearchResults(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      filteredFiles = allFiles
          .where((file) =>
              file['name'] != null &&
              file['name']!.toLowerCase().contains(searchQuery))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.teal[800]!,
                Colors.teal[600]!,
                Colors.teal[400]!,
              ],
            ),
          ),
        ),
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.arrow_back_ios,
              color: Colors.white,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.folder_shared,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'ملفات Google Drive',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        centerTitle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              onChanged: updateSearchResults,
              decoration: InputDecoration(
                hintText: 'Search for a file...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
          ),
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          'Total Files: $totalFilesCount',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filteredFiles.length,
                          itemBuilder: (context, index) {
                            final file = filteredFiles[index];
                            return ListTile(
                              title: Text(file['name'] ?? 'No Name'),
                              subtitle: Text('Region: ${file['region']}'),
                              trailing: const Icon(Icons.arrow_forward),
                              onTap: () => openInGoogleEarth(
                                  file['url'], file['name'] ?? 'file.kml'),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
