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

  // ─── Responsive helpers ───
  bool get _isPhone =>
      MediaQuery.of(context).size.width < 500;

  double _fs(double size) => _isPhone ? size * 0.85 : size;

  double _ic(double size) => _isPhone ? size * 0.85 : size;

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
        toolbarHeight: _isPhone ? 44 : 50,
        iconTheme: IconThemeData(size: _ic(20)),
        title: Text('TKTATs', style: TextStyle(fontSize: _fs(16), fontWeight: FontWeight.w600)),
        backgroundColor: Colors.blue[600],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, size: _ic(20)),
            onPressed: fetchTKTATs,
          ),
        ],
      ),
      body: Container(
        padding: EdgeInsets.all(_isPhone ? 10.0 : 16.0),
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
            fontSize: _fs(16),
            color: Colors.red[600],
          ),
          textAlign: TextAlign.center,
        ),
      );
    } else if (tktats.isEmpty) {
      return Center(
        child: Text(
          'لا توجد TKTATs متاحة',
          style: TextStyle(fontSize: _fs(18)),
        ),
      );
    } else {
      return ListView.builder(
        itemCount: tktats.length,
        itemBuilder: (context, index) {
          final tktat = tktats[index];
          return Card(
            margin: EdgeInsets.symmetric(vertical: _isPhone ? 5 : 8),
            child: ListTile(
              dense: _isPhone,
              title: Text(tktat['title'] ?? 'بدون عنوان',
                  style: TextStyle(fontSize: _fs(14))),
              subtitle: Text(tktat['description'] ?? 'بدون وصف',
                  style: TextStyle(fontSize: _fs(12))),
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
