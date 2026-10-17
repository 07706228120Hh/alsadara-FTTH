using Xunit;

namespace Sadara.Integration.Tests.Support;

/// <summary>
/// تعريف مجموعة xUnit تشارك حاوية Postgres واحدة بين أصناف الاختبار التي تعزل بياناتها ذاتياً
/// (شركات/مستخدمون بمعرّفات Guid جديدة لكل اختبار، ولا تعتمد على قاعدة فارغة):
/// AccountingTenantIsolationTests و InternalDataJwtIsolationTests.
///
/// Isolation rule: every xUnit collection gets its own <see cref="PostgresFixture"/> instance, i.e. its own
/// container and database. Test classes that need an EMPTY database (absolute counts, global resets) must
/// own a dedicated collection — see <see cref="PostgresSummaryCollection"/>, "PostgresTasksIsolation",
/// "FtthIsolationPostgres". Do not add such classes here.
/// </summary>
[CollectionDefinition("Postgres")]
public sealed class PostgresCollection : ICollectionFixture<PostgresFixture>
{
}

/// <summary>
/// Dedicated collection (own container/database) for <c>ServiceRequestsSummaryTests</c>.
/// The summary tests assert absolute totals and wipe Users/Companies between tests, so they must not
/// share a database with suites that leave dependent rows (EmployeeSalaries, CashBoxes, logs, ...),
/// otherwise the reset fails with FK violations (23503) or the totals become order-dependent.
/// </summary>
[CollectionDefinition(Name)]
public sealed class PostgresSummaryCollection : ICollectionFixture<PostgresFixture>
{
    public const string Name = "PostgresSummary";
}
