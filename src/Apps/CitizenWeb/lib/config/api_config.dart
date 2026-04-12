class ApiConfig {
  // ═══════════════════════════════════════════════════════════════
  // تبديل بين الخادم المحلي والإنتاج
  // غيّر إلى true للاختبار المحلي
  // ═══════════════════════════════════════════════════════════════
  static const bool useLocalApi = false;

  // Production API server
  static const String _productionUrl = 'https://api.ramzalsadara.tech';
  // Local development API server
  static const String _localUrl = 'http://localhost:5000';

  static const String baseUrl = useLocalApi ? _localUrl : _productionUrl;
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

  // Agent Endpoints
  static const String agentLogin = '$apiVersion/agents/login';
  static const String agentProfile = '$apiVersion/agents/me';
  static const String agentMyTransactions =
      '$apiVersion/agents/me/transactions';
  static const String agentCreateServiceRequest =
      '$apiVersion/agents/me/service-request';
  static const String agentMyServiceRequests =
      '$apiVersion/agents/me/service-requests';
  static const String agentTransactions =
      '$apiVersion/agents'; // /{id}/transactions
  static const String agentCharge = '$apiVersion/agents'; // /{id}/charge
  static const String agentPayment =
      '$apiVersion/agents'; // /{id}/payment (admin)
  static const String agentSelfPayment =
      '$apiVersion/agents/me/payment'; // agent self-payment
  static const String agentBalanceRequest =
      '$apiVersion/agents/me/balance-request';
  static const String agentChangePassword =
      '$apiVersion/agents/me/change-password';
  static const String agentAccountingSummary =
      '$apiVersion/agents/me/accounting';

  // Internet Plans (public)
  static const String publicInternetPlans = '$apiVersion/citizen/plans';

  // Citizen Service Requests
  static const String citizenDeliveryWithdrawal = '$apiVersion/citizen/delivery-withdrawal';

  // Service Requests
  static const String serviceRequests = '$apiVersion/servicerequests';
  static const String serviceRequestServices =
      '$apiVersion/servicerequests/services';

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}
