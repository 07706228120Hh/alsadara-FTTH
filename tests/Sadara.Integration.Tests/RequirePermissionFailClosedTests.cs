using Sadara.API.Authorization;
using Xunit;

namespace Sadara.Integration.Tests;

/// <summary>
/// Pins down RequirePermissionAttribute.HasPermission — in particular the fail-open vs fail-closed
/// behaviour on empty permissions. The platform currently defaults to fail-open (legacy users with no
/// V2 permissions are not blocked); the documented remediation is to stamp V2 permissions for all users
/// then enable the global Authz:FailClosed flag. These tests guarantee the fail-closed path denies access,
/// so the remediation is safe to switch on. Pure logic — no database, no permission is granted to anyone.
/// </summary>
public class RequirePermissionFailClosedTests
{
    private const string Granted = "{\"accounting\":{\"view\":true,\"edit\":false}}";
    private const string ChildHierarchy = "{\"accounting\":{\"view\":true}}";
    private const string ParentClosed = "{\"accounting\":{\"view\":false}}";
    private const string ManageViaEdit = "{\"sas_agent\":{\"edit\":true}}";

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    public void EmptyPermissions_FailOpen_Grants_FailClosed_Denies(string? json)
    {
        // Current default (fail-open): empty ⇒ allowed (legacy users not blocked).
        Assert.True(RequirePermissionAttribute.HasPermission(json, "accounting", "view", failClosed: false));
        // Remediation (fail-closed): empty ⇒ denied. This is what enabling Authz:FailClosed must guarantee.
        Assert.False(RequirePermissionAttribute.HasPermission(json, "accounting", "view", failClosed: true));
    }

    [Fact]
    public void ExplicitGrant_Allows_RegardlessOfFailClosed()
    {
        Assert.True(RequirePermissionAttribute.HasPermission(Granted, "accounting", "view", failClosed: false));
        Assert.True(RequirePermissionAttribute.HasPermission(Granted, "accounting", "view", failClosed: true));
    }

    [Fact]
    public void ExplicitlyAbsentOrFalseAction_Denies_EvenFailOpen()
    {
        // The column is present (not empty) ⇒ fail-open does NOT apply; an action that is false/absent is denied.
        Assert.False(RequirePermissionAttribute.HasPermission(Granted, "accounting", "edit", failClosed: false));
        Assert.False(RequirePermissionAttribute.HasPermission(Granted, "hr", "view", failClosed: false));
    }

    [Fact]
    public void Hierarchy_ParentOpen_ChildInherits_ParentClosed_ChildDenied()
    {
        Assert.True(RequirePermissionAttribute.HasPermission(ChildHierarchy, "accounting.journals", "view", failClosed: false));
        Assert.False(RequirePermissionAttribute.HasPermission(ParentClosed, "accounting.journals", "view", failClosed: false));
    }

    [Fact]
    public void ManageAction_SatisfiedByWriteCapability()
    {
        Assert.True(RequirePermissionAttribute.HasPermission(ManageViaEdit, "sas_agent", "manage", failClosed: true));
        Assert.False(RequirePermissionAttribute.HasPermission("{\"sas_agent\":{\"view\":true}}", "sas_agent", "manage", failClosed: true));
    }

    [Fact]
    public void MalformedJson_Denies()
    {
        Assert.False(RequirePermissionAttribute.HasPermission("{ not json", "accounting", "view", failClosed: false));
    }
}
