import 'dart:convert';
import 'dart:io';

void main() async {
  // تجاهل أخطاء SSL
  HttpOverrides.global = MyHttpOverrides();

  final client = HttpClient();

  // تسجيل الدخول
  final loginRequest = await client.postUrl(
    Uri.parse('https://72.61.183.61/api/companies/login'),
  );
  loginRequest.headers.contentType = ContentType.json;
  loginRequest.write(
    jsonEncode({
      'companyCode': 'SADARA',
      'username': '0770',
      'password': '123456',
    }),
  );

  final loginResponse = await loginRequest.close();
  final loginBody = await loginResponse.transform(utf8.decoder).join();
  final loginData = jsonDecode(loginBody);

  print('=== Login Response ===');
  print('Success: ${loginData['success']}');

  if (loginData['success'] == true) {
    final token = loginData['data']['Token'];
    final companyId = loginData['data']['Company']['Id'];

    // جلب الموظفين
    final empRequest = await client.getUrl(
      Uri.parse('https://72.61.183.61/api/companies/$companyId/employees'),
    );
    empRequest.headers.add('Authorization', 'Bearer $token');

    final empResponse = await empRequest.close();
    final empBody = await empResponse.transform(utf8.decoder).join();
    final empData = jsonDecode(empBody);

    print('\n=== Employees ===');
    if (empData['success'] == true) {
      print('Total: ${empData['total']}');
      for (var emp in empData['data']) {
        print('- ${emp['FullName']} | ${emp['PhoneNumber']} | ${emp['Role']}');
      }
    } else {
      print('Error: ${empData['message']}');
    }
  }

  client.close();
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
