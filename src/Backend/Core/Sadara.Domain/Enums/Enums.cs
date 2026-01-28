namespace Sadara.Domain.Enums;

public enum UserRole
{
    Customer = 0,
    Merchant = 1,
    Driver = 2,
    Admin = 3,
    SuperAdmin = 4
}

public enum OrderStatus
{
    Pending = 0,
    Confirmed = 1,
    Processing = 2,
    Shipped = 3,
    Delivered = 4,
    Cancelled = 5,
    Refunded = 6
}

public enum PaymentStatus
{
    Pending = 0,
    Processing = 1,
    Success = 2,
    Failed = 3,
    Refunded = 4,
    Cancelled = 5
}

public enum PaymentMethod
{
    CashOnDelivery = 0,
    ZainCash = 1,
    FastPay = 2,
    Wallet = 3,
    BankTransfer = 4
}

public enum CustomerType
{
    New = 0,
    Regular = 1,
    VIP = 2,
    Blacklisted = 3
}

public enum SubscriptionPlan
{
    Free = 0,
    Basic = 1,
    Pro = 2,
    Enterprise = 3
}

public enum NotificationType
{
    OrderUpdate = 0,
    Payment = 1,
    Promotion = 2,
    System = 3
}

public enum Gender
{
    Male = 0,
    Female = 1,
    Other = 2
}

public enum DiscountType
{
    Percentage = 0,
    Fixed = 1
}
