/// نموذج الاستجابة الموحد من API
class ApiResponse<T> {
  final bool success;
  final T? data;
  final String? message;
  final int statusCode;
  final List<String>? errors;

  ApiResponse._({
    required this.success,
    this.data,
    this.message,
    required this.statusCode,
    this.errors,
  });

  /// استجابة ناجحة
  factory ApiResponse.success(T data, {int statusCode = 200, String? message}) {
    return ApiResponse._(
      success: true,
      data: data,
      statusCode: statusCode,
      message: message,
    );
  }

  /// استجابة فاشلة
  factory ApiResponse.error(
    String message, {
    int statusCode = 500,
    List<String>? errors,
  }) {
    return ApiResponse._(
      success: false,
      message: message,
      statusCode: statusCode,
      errors: errors,
    );
  }

  /// من JSON
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? parser, {
    required int statusCode,
  }) {
    final success = json['success'] == true;

    return ApiResponse._(
      success: success,
      data: success && json['data'] != null && parser != null
          ? parser(json['data'])
          : null,
      message: json['message']?.toString(),
      statusCode: statusCode,
      errors: json['errors'] != null ? List<String>.from(json['errors']) : null,
    );
  }

  // ============================================
  // Helper Methods
  // ============================================

  bool get isSuccess => success;
  bool get isError => !success;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500;
  bool get isClientError => statusCode >= 400 && statusCode < 500;

  /// تحويل إلى نوع آخر
  ApiResponse<R> map<R>(R Function(T) mapper) {
    if (success && data != null) {
      return ApiResponse.success(mapper(data as T), statusCode: statusCode);
    }
    return ApiResponse.error(message ?? 'Unknown error',
        statusCode: statusCode, errors: errors);
  }

  /// تنفيذ إذا كان ناجح
  void whenSuccess(void Function(T data) onSuccess) {
    if (success && data != null) {
      onSuccess(data as T);
    }
  }

  /// تنفيذ إذا كان فاشل
  void whenError(void Function(String message, int statusCode) onError) {
    if (!success) {
      onError(message ?? 'Unknown error', statusCode);
    }
  }

  /// fold - تنفيذ أحد الخيارين
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(String message, int statusCode) onError,
  }) {
    if (success && data != null) {
      return onSuccess(data as T);
    }
    return onError(message ?? 'Unknown error', statusCode);
  }

  @override
  String toString() {
    return 'ApiResponse(success: $success, statusCode: $statusCode, message: $message, data: $data)';
  }
}
