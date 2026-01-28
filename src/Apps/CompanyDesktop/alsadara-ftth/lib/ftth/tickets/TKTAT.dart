import 'package:flutter/material.dart';

class TKTAT extends StatefulWidget {
  final String authToken;

  const TKTAT({super.key, required this.authToken});

  @override
  State<TKTAT> createState() => _TKTATState();
}

class _TKTATState extends State<TKTAT> {
  List<dynamic> tktats = [];
  bool isLoading = true;
  String message = "";

  @override
  void initState() {
    super.initState();
    fetchTKTATs();
  }

  Future<void> fetchTKTATs() async {
    setState(() {
      isLoading = true;
      message = "";
    });

    try {
      // إضافة منطق جلب TKTATs هنا
      await Future.delayed(const Duration(seconds: 1)); // محاكاة تحميل

      setState(() {
        tktats = []; // قائمة فارغة مؤقتاً
        isLoading = false;
        message = tktats.isEmpty ? "لا توجد TKTATs متاحة" : "";
      });
    } catch (e) {
      setState(() {
        message = "حدث خطأ أثناء جلب البيانات: $e";
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 50,
        iconTheme: const IconThemeData(size: 20),
        title: const Text('TKTATs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: fetchTKTATs,
          ),
        ],
      ),
      body: Container(
        padding: const EdgeInsets.all(16.0),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    } else if (message.isNotEmpty) {
      return Center(
        child: Text(
          message,
          style: TextStyle(
            fontSize: 16,
            color: Colors.red[600],
          ),
          textAlign: TextAlign.center,
        ),
      );
    } else if (tktats.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد TKTATs متاحة',
          style: TextStyle(fontSize: 18),
        ),
      );
    } else {
      return ListView.builder(
        itemCount: tktats.length,
        itemBuilder: (context, index) {
          final tktat = tktats[index];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              title: Text(tktat['title'] ?? 'بدون عنوان'),
              subtitle: Text(tktat['description'] ?? 'بدون وصف'),
              onTap: () {
                // إضافة منطق فتح تفاصيل TKTAT
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم النقر على: ${tktat['title'] ?? 'TKTAT'}'),
                  ),
                );
              },
            ),
          );
        },
      );
    }
  }
}
