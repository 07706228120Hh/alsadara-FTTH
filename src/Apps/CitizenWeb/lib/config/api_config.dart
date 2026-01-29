class ApiConfig {
  // Use HTTP for development (browser doesn't accept self-signed SSL)
  // For production, use proper SSL certificate
  static const String baseUrl = 'http://72.61.183.61';
  static const String apiVersion = '/api';

  // Citizen Endpoints
  static const String citizenRegister = '$apiVersion/citizen/register';
  static const String citizenLogin = '$apiVersion/citizen/login';
  static const String citizenVerifyPhone = '$apiVersion/citizen/verify-phone';
  static const String citizenProfile = '$apiVersion/citizen/profile';
  static const String citizenForgotPassword =
      '$apiVersion/citizen/forgot-password';
  static const String citizenResetPassword =
      '$apiVersion/citizen/reset-password';

  // Plans
  static const String internetPlans = '$apiVersion/citizen/plans';
  static const String featuredPlans = '$apiVersion/citizen/plans/featured';

  // Subscriptions
  static const String subscriptions = '$apiVersion/citizen/subscriptions';
  static const String activeSubscription =
      '$apiVersion/citizen/subscriptions/active';

  // Support
  static const String supportTickets = '$apiVersion/citizen/support';

  // Store
  static const String storeCategories = '$apiVersion/citizen/store/categories';
  static const String storeProducts = '$apiVersion/citizen/store/products';
  static const String storeOrders = '$apiVersion/citizen/store/orders';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
