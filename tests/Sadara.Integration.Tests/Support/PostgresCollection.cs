using Xunit;

namespace Sadara.Integration.Tests.Support;

/// <summary>
/// تعريف مجموعة xUnit تشارك حاوية Postgres واحدة عبر كل اختبارات الملخّص
/// (إقلاع حاوية واحد بدل واحدة لكل صنف/اختبار). لا يحوي كوداً — مجرد ربط للمُهيّئ.
/// </summary>
[CollectionDefinition("Postgres")]
public sealed class PostgresCollection : ICollectionFixture<PostgresFixture>
{
}
