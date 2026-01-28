using AutoMapper;
using Sadara.Application.DTOs;
using Sadara.Domain.Entities;

namespace Sadara.Application.Mapping;

public class MappingProfile : Profile
{
    public MappingProfile()
    {
        CreateMap<User, UserDto>();
        CreateMap<RegisterRequest, User>();

        CreateMap<Merchant, MerchantDto>();
        CreateMap<CreateMerchantRequest, Merchant>();
        CreateMap<UpdateMerchantRequest, Merchant>()
            .ForAllMembers(opt => opt.Condition((src, dest, srcMember) => srcMember != null));

        CreateMap<Customer, CustomerDto>();
        CreateMap<CreateCustomerRequest, Customer>();
        CreateMap<UpdateCustomerRequest, Customer>()
            .ForAllMembers(opt => opt.Condition((src, dest, srcMember) => srcMember != null));

        CreateMap<Product, ProductDto>()
            .ForMember(dest => dest.Images, opt => opt.MapFrom(src =>
                string.IsNullOrEmpty(src.Images) ? null : src.Images.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries)));
        CreateMap<Category, CategoryDto>();
        CreateMap<ProductVariant, ProductVariantDto>();
        CreateMap<CreateProductRequest, Product>();

        CreateMap<Order, OrderDto>();
        CreateMap<OrderItem, OrderItemDto>();
        CreateMap<OrderStatusHistory, OrderStatusHistoryDto>();
        CreateMap<CreateOrderRequest, Order>();

        CreateMap<Payment, PaymentDto>();
        CreateMap<Notification, NotificationDto>();
        CreateMap<CreateNotificationRequest, Notification>();
    }
}
