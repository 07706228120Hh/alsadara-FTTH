import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveFilesPage extends StatefulWidget {
  const GoogleDriveFilesPage({super.key});

  @override
  GoogleDriveFilesPageState createState() => GoogleDriveFilesPageState();
}

class GoogleDriveFilesPageState extends State<GoogleDriveFilesPage> {
  final String folderId =
      '1HWckEov1vjxyRZcCVpUX8YzJJCyWRsQP'; // معرف المجلد الرئيسي
  final String apiKey =
      'AIzaSyD43g0P8yiwnELcZRoThWCjWejiHLEBPNw'; // مفتاح API الخاص بك
  String searchQuery = ''; // النص المدخل للبحث

  List<Map<String, String>> allFiles = []; // قائمة بجميع الملفات
  List<Map<String, String>> filteredFiles = []; // قائمة الملفات المفلترة
  Map<String, int> folderFilesCount = {}; // عدد الملفات في كل مجلد
  int totalFiles = 0; // العدد الكلي للملفات (الزونات)

  Future<void> fetchAllFiles(String parentId, String parentRegion) async {
    final url =
        'https://www.googleapis.com/drive/v3/files?q=\'$parentId\'+in+parents&key=$apiKey';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      int filesInCurrentFolder = 0;

      for (var file in data['files']) {
        if (file['mimeType'] == 'application/vnd.google-apps.folder') {
          await fetchAllFiles(file['id'], file['name']);
        } else {
          filesInCurrentFolder++;
          setState(() {
            allFiles.add({
              "name": file['name'],
              "region": parentRegion,
              "url": 'https://drive.google.com/file/d/${file['id']}/view',
            });
          });
        }
      }

      if (parentRegion != 'المنطقة الرئيسية') {
        setState(() {
          folderFilesCount[parentRegion] = filesInCurrentFolder;
          totalFiles += filesInCurrentFolder;
          filteredFiles = allFiles;
        });
      }
    } else {
      throw Exception('Failed to load files');
    }
  }

  Future<void> openUrl(String url) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      throw 'تعذر فتح الرابط: $url';
    }
  }

  void updateSearchResults(String query) {
    setState(() {
      searchQuery = query.toLowerCase();
      filteredFiles = allFiles
          .where((file) => file['name']!.toLowerCase().contains(searchQuery))
          .toList();
    });
  }

  @override
  void initState() {
    super.initState();
    fetchAllFiles(folderId, 'المنطقة الرئيسية');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'البحث عن الملفات',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue[800],
      ),
      body: Container(
        color: Colors.blue[50],
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'إجمالي عدد الزونات: $totalFiles',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                children: folderFilesCount.entries.map((entry) {
                  return Container(
                    width: 150,
                    margin: EdgeInsets.symmetric(horizontal: 8.0),
                    padding: EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8.0),
                      color: Colors.blue[100],
                      border: Border.all(color: Colors.blue[800]!, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          entry.key,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'عدد الملفات: ${entry.value}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            Divider(color: Colors.blue[800]),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                onChanged: updateSearchResults,
                decoration: InputDecoration(
                  hintText: 'ابحث عن ملف...',
                  hintStyle: TextStyle(color: Colors.black),
                  prefixIcon: Icon(Icons.search, color: Colors.blue[800]),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Colors.blue[800]!),
                  ),
                ),
                style: TextStyle(color: Colors.black),
              ),
            ),
            Expanded(
              child: filteredFiles.isEmpty
                  ? Center(
                      child: Text(
                        searchQuery.isEmpty
                            ? 'لا توجد ملفات محملة.'
                            : 'لا توجد ملفات مطابقة للبحث.',
                        style: TextStyle(fontSize: 16, color: Colors.black),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredFiles.length,
                      itemBuilder: (context, index) {
                        return Card(
                          margin: EdgeInsets.symmetric(
                              vertical: 4.0, horizontal: 8.0),
                          child: ListTile(
                            leading: Icon(Icons.file_present,
                                color: Colors.blue[800]),
                            title: Text(
                              filteredFiles[index]['name']!,
                              style: TextStyle(color: Colors.black),
                            ),
                            subtitle: Text(
                              'المنطقة: ${filteredFiles[index]['region']}',
                              style: TextStyle(color: Colors.black),
                            ),
                            trailing: Icon(Icons.arrow_forward,
                                color: Colors.blue[800]),
                            onTap: () => openUrl(filteredFiles[index]['url']!),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      primarySwatch: Colors.blue,
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: Colors.black),
        bodyMedium: TextStyle(color: Colors.black),
      ),
    ),
    home: GoogleDriveFilesPage(),
  ));
}
