using FluentValidation;
using Sadara.Application.DTOs;

namespace Sadara.Application.Validators;

#region Authentication Validators

public class LoginRequestValidator : AbstractValidator<LoginRequest>
{
    public LoginRequestValidator()
    {
        RuleFor(x => x.PhoneNumber)
            .NotEmpty().WithMessage("رقم الهاتف مطلوب")
            .Matches(@"^\+?[0-9]{10,15}$").WithMessage("رقم الهاتف غير صالح");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("كلمة المرور مطلوبة")
            .MinimumLength(6).WithMessage("كلمة المرور يجب أن تكون 6 أحرف على الأقل");
    }
}

public class RegisterRequestValidator : AbstractValidator<RegisterRequest>
{
    public RegisterRequestValidator()
    {
        RuleFor(x => x.FullName)
            .NotEmpty().WithMessage("الاسم الكامل مطلوب")
            .MaximumLength(100).WithMessage("الاسم يجب أن لا يتجاوز 100 حرف");

        RuleFor(x => x.PhoneNumber)
            .NotEmpty().WithMessage("رقم الهاتف مطلوب")
            .Matches(@"^\+?[0-9]{10,15}$").WithMessage("رقم الهاتف غير صالح");

        RuleFor(x => x.Password)
            .NotEmpty().WithMessage("كلمة المرور مطلوبة")
            .MinimumLength(8).WithMessage("كلمة المرور يجب أن تكون 8 أحرف على الأقل")
            .Matches(@"[A-Z]").WithMessage("كلمة المرور يجب أن تحتوي على حرف كبير")
            .Matches(@"[a-z]").WithMessage("كلمة المرور يجب أن تحتوي على حرف صغير")
            .Matches(@"[0-9]").WithMessage("كلمة المرور يجب أن تحتوي على رقم");

        RuleFor(x => x.Email)
            .EmailAddress().WithMessage("البريد الإلكتروني غير صالح")
            .When(x => !string.IsNullOrEmpty(x.Email));
    }
}

public class ChangePasswordRequestValidator : AbstractValidator<ChangePasswordRequest>
{
    public ChangePasswordRequestValidator()
    {
        RuleFor(x => x.CurrentPassword)
            .NotEmpty().WithMessage("كلمة المرور الحالية مطلوبة");

        RuleFor(x => x.NewPassword)
            .NotEmpty().WithMessage("كلمة المرور الجديدة مطلوبة")
            .MinimumLength(8).WithMessage("كلمة المرور يجب أن تكون 8 أحرف على الأقل")
            .Matches(@"[A-Z]").WithMessage("كلمة المرور يجب أن تحتوي على حرف كبير")
            .Matches(@"[a-z]").WithMessage("كلمة المرور يجب أن تحتوي على حرف صغير")
            .Matches(@"[0-9]").WithMessage("كلمة المرور يجب أن تحتوي على رقم")
            .NotEqual(x => x.CurrentPassword).WithMessage("كلمة المرور الجديدة يجب أن تختلف عن الحالية");

        RuleFor(x => x.ConfirmPassword)
            .Equal(x => x.NewPassword).WithMessage("تأكيد كلمة المرور غير متطابق");
    }
}

#endregion

#region Merchant Validators

public class CreateMerchantRequestValidator : AbstractValidator<CreateMerchantRequest>
{
    public CreateMerchantRequestValidator()
    {
        RuleFor(x => x.BusinessName)
            .NotEmpty().WithMessage("اسم النشاط التجاري مطلوب")
            .MaximumLength(200).WithMessage("اسم النشاط يجب أن لا يتجاوز 200 حرف");

        RuleFor(x => x.City)
            .NotEmpty().WithMessage("المدينة مطلوبة")
            .MaximumLength(100).WithMessage("اسم المدينة يجب أن لا يتجاوز 100 حرف");

        RuleFor(x => x.PhoneNumber)
            .NotEmpty().WithMessage("رقم الهاتف مطلوب")
            .Matches(@"^\+?[0-9]{10,15}$").WithMessage("رقم الهاتف غير صالح");

        RuleFor(x => x.Email)
            .EmailAddress().WithMessage("البريد الإلكتروني غير صالح")
            .When(x => !string.IsNullOrEmpty(x.Email));

        RuleFor(x => x.Website)
            .Matches(@"^https?://.*").WithMessage("رابط الموقع غير صالح")
            .When(x => !string.IsNullOrEmpty(x.Website));
    }
}

#endregion

#region Customer Validators

public class CreateCustomerRequestValidator : AbstractValidator<CreateCustomerRequest>
{
    public CreateCustomerRequestValidator()
    {
        RuleFor(x => x.FullName)
            .NotEmpty().WithMessage("الاسم الكامل مطلوب")
            .MaximumLength(100).WithMessage("الاسم يجب أن لا يتجاوز 100 حرف");

        RuleFor(x => x.PhoneNumber)
            .NotEmpty().WithMessage("رقم الهاتف مطلوب")
            .Matches(@"^\+?[0-9]{10,15}$").WithMessage("رقم الهاتف غير صالح");

        RuleFor(x => x.City)
            .NotEmpty().WithMessage("المدينة مطلوبة")
            .MaximumLength(100).WithMessage("اسم المدينة يجب أن لا يتجاوز 100 حرف");

        RuleFor(x => x.Email)
            .EmailAddress().WithMessage("البريد الإلكتروني غير صالح")
            .When(x => !string.IsNullOrEmpty(x.Email));
    }
}

public class UpdateCustomerRequestValidator : AbstractValidator<UpdateCustomerRequest>
{
    public UpdateCustomerRequestValidator()
    {
        RuleFor(x => x.FullName)
            .MaximumLength(100).WithMessage("الاسم يجب أن لا يتجاوز 100 حرف")
            .When(x => !string.IsNullOrEmpty(x.FullName));

        RuleFor(x => x.PhoneNumber)
            .Matches(@"^\+?[0-9]{10,15}$").WithMessage("رقم الهاتف غير صالح")
            .When(x => !string.IsNullOrEmpty(x.PhoneNumber));

        RuleFor(x => x.City)
            .MaximumLength(100).WithMessage("اسم المدينة يجب أن لا يتجاوز 100 حرف")
            .When(x => !string.IsNullOrEmpty(x.City));

        RuleFor(x => x.Email)
            .EmailAddress().WithMessage("البريد الإلكتروني غير صالح")
            .When(x => !string.IsNullOrEmpty(x.Email));
    }
}

#endregion

#region Product Validators

public class CreateProductRequestValidator : AbstractValidator<CreateProductRequest>
{
    public CreateProductRequestValidator()
    {
        RuleFor(x => x.Name)
            .NotEmpty().WithMessage("اسم المنتج مطلوب")
            .MaximumLength(200).WithMessage("اسم المنتج يجب أن لا يتجاوز 200 حرف");

        RuleFor(x => x.Price)
            .GreaterThan(0).WithMessage("السعر يجب أن يكون أكبر من صفر");

        RuleFor(x => x.DiscountPrice)
            .LessThan(x => x.Price).WithMessage("سعر الخصم يجب أن يكون أقل من السعر الأصلي")
            .When(x => x.DiscountPrice.HasValue && x.DiscountPrice > 0);

        RuleFor(x => x.StockQuantity)
            .GreaterThanOrEqualTo(0).WithMessage("الكمية لا يمكن أن تكون سالبة");
    }
}

#endregion

#region Order Validators

public class CreateOrderRequestValidator : AbstractValidator<CreateOrderRequest>
{
    public CreateOrderRequestValidator()
    {
        RuleFor(x => x.CustomerId)
            .GreaterThan(0).WithMessage("رقم العميل غير صالح");

        RuleFor(x => x.Items)
            .NotEmpty().WithMessage("الطلب يجب أن يحتوي على منتج واحد على الأقل");

        RuleForEach(x => x.Items).SetValidator(new CreateOrderItemRequestValidator());
    }
}

public class CreateOrderItemRequestValidator : AbstractValidator<CreateOrderItemRequest>
{
    public CreateOrderItemRequestValidator()
    {
        RuleFor(x => x.ProductId)
            .NotEmpty().WithMessage("رقم المنتج مطلوب");

        RuleFor(x => x.Quantity)
            .GreaterThan(0).WithMessage("الكمية يجب أن تكون أكبر من صفر");
    }
}

public class UpdateOrderStatusRequestValidator : AbstractValidator<UpdateOrderStatusRequest>
{
    public UpdateOrderStatusRequestValidator()
    {
        RuleFor(x => x.Status)
            .IsInEnum().WithMessage("حالة الطلب غير صالحة");
    }
}

#endregion

#region Payment Validators

public class CreatePaymentRequestValidator : AbstractValidator<CreatePaymentRequest>
{
    public CreatePaymentRequestValidator()
    {
        RuleFor(x => x.OrderId)
            .NotEmpty().WithMessage("رقم الطلب مطلوب");

        RuleFor(x => x.Amount)
            .GreaterThan(0).WithMessage("المبلغ يجب أن يكون أكبر من صفر");

        RuleFor(x => x.Method)
            .IsInEnum().WithMessage("طريقة الدفع غير صالحة");
    }
}

public class TopUpWalletRequestValidator : AbstractValidator<TopUpWalletRequest>
{
    public TopUpWalletRequestValidator()
    {
        RuleFor(x => x.Amount)
            .GreaterThan(0).WithMessage("المبلغ يجب أن يكون أكبر من صفر")
            .LessThanOrEqualTo(1000000).WithMessage("المبلغ يجب أن لا يتجاوز مليون");

        RuleFor(x => x.Method)
            .IsInEnum().WithMessage("طريقة الدفع غير صالحة");
    }
}

#endregion
