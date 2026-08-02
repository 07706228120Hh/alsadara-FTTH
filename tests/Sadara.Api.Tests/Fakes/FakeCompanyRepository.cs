using System.Linq.Expressions;
using Sadara.Domain.Entities;
using Sadara.Domain.Interfaces;

namespace Sadara.Api.Tests.Fakes;

/// <summary>
/// مستودع شركات وهمي يدوي (بلا Moq).
/// الكونترولر GetNodeConfig لا يستدعي سوى GetByIdAsync؛ بقية الأعضاء غير مدعومة عمداً
/// لضمان أن أي استدعاء غير متوقّع يفشل بوضوح بدل أن يمر بصمت.
/// </summary>
public sealed class FakeCompanyRepository : IRepository<Company, Guid>
{
    private readonly Dictionary<Guid, Company> _store = new();

    /// <summary>يضيف/يستبدل شركة في المخزن الوهمي.</summary>
    public FakeCompanyRepository Seed(Company company)
    {
        _store[company.Id] = company;
        return this;
    }

    public Task<Company?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        _store.TryGetValue(id, out var company);
        return Task.FromResult<Company?>(company);
    }

    // ===== أعضاء غير مستخدمة في هذا الاختبار — تُرمى صراحةً =====
    public Task<IEnumerable<Company>> GetAllAsync(CancellationToken ct = default)
        => throw new NotSupportedException();

    public Task<IEnumerable<Company>> FindAsync(Expression<Func<Company, bool>> predicate, CancellationToken ct = default)
        => throw new NotSupportedException();

    public Task<Company?> FirstOrDefaultAsync(Expression<Func<Company, bool>> predicate, CancellationToken ct = default)
        => throw new NotSupportedException();

    public Task<Company> AddAsync(Company entity, CancellationToken ct = default)
        => throw new NotSupportedException();

    public void Update(Company entity) => throw new NotSupportedException();

    public void Delete(Company entity) => throw new NotSupportedException();

    public Task<bool> AnyAsync(Expression<Func<Company, bool>> predicate, CancellationToken ct = default)
        => throw new NotSupportedException();

    public Task<int> CountAsync(Expression<Func<Company, bool>>? predicate = null, CancellationToken ct = default)
        => throw new NotSupportedException();

    public IQueryable<Company> AsQueryable() => throw new NotSupportedException();

    public Task<IEnumerable<Company>> GetWithIncludesAsync(
        Expression<Func<Company, bool>>? filter,
        CancellationToken ct,
        params Expression<Func<Company, object>>[] includes)
        => throw new NotSupportedException();
}
