class AppBreakpoints {
  // Common breakpoints
  static const double mobileMax = 600; // <= 600
  static const double tabletMax = 1024; // >600 && <=1024
  static const double desktopMax = 1440; // >1024 && <=1440

  static bool isMobile(double width) => width <= mobileMax;
  static bool isTablet(double width) => width > mobileMax && width <= tabletMax;
  static bool isDesktop(double width) => width > tabletMax && width <= desktopMax;
  static bool isLargeDesktop(double width) => width > desktopMax;
}
