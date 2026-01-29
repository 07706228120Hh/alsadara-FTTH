using Npgsql;

// محاولة عدة طرق للاتصال
var connectionStrings = new[]
{
    "Host=72.61.183.61;Port=5432;Database=sadara_db;Username=sadara_user;Password=sadara_secure_password_2024;Timeout=60;Command Timeout=60;Pooling=false",
    "Host=72.61.183.61;Port=5432;Database=sadara_db;Username=sadara_user;Password=sadara_secure_password_2024;SSL Mode=Disable;Timeout=60;Command Timeout=60",
    "Host=72.61.183.61;Port=5432;Database=sadara_db;Username=sadara_user;Password=sadara_secure_password_2024;SSL Mode=Prefer;Timeout=60;Command Timeout=60",
    "Server=72.61.183.61;Port=5432;Database=sadara_db;User Id=sadara_user;Password=sadara_secure_password_2024;Timeout=60;Command Timeout=60"
};

NpgsqlConnection? successfulConnection = null;
string? successfulConnectionString = null;

foreach (var connStr in connectionStrings)
{
    try
    {
        Console.WriteLine($"🔌 محاولة الاتصال...");
        Console.WriteLine($"   Connection String: {connStr.Replace("sadara_secure_password_2024", "***")}");
        
        using var testConn = new NpgsqlConnection(connStr);
        testConn.Open();
        Console.WriteLine("✅ تم الاتصال بنجاح!");
        
        successfulConnection = new NpgsqlConnection(connStr);
        successfulConnectionString = connStr;
        break;
    }
    catch (Exception ex)
    {
        Console.WriteLine($"❌ فشل: {ex.Message}");
        Console.WriteLine();
    }
}

if (successfulConnection == null)
{
    Console.WriteLine("❌ فشلت جميع محاولات الاتصال.");
    Console.WriteLine("\nالرجاء التحقق من:");
    Console.WriteLine("1. VPS يعمل ومتاح");
    Console.WriteLine("2. PostgreSQL يعمل على البورت 5432");
    Console.WriteLine("3. Firewall يسمح بالاتصالات الخارجية");
    Console.WriteLine("4. pg_hba.conf يسمح بالاتصالات من IP الخاص بك");
    Environment.Exit(1);
}

try
{
    successfulConnection.Open();
    Console.WriteLine("\n✅ تم الاتصال بنجاح!");
    Console.WriteLine($"استخدام: {successfulConnectionString?.Replace("sadara_secure_password_2024", "***")}");

    Console.WriteLine("\n✅ تم الاتصال بنجاح!");
    Console.WriteLine($"استخدام: {successfulConnectionString?.Replace("sadara_secure_password_2024", "***")}");

    // تطبيق Migration
    var sql = @"
DO $$
BEGIN
    -- إضافة عمود IsLinkedToCitizenPortal
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'Companies' AND column_name = 'IsLinkedToCitizenPortal'
    ) THEN
        ALTER TABLE ""Companies"" 
        ADD COLUMN ""IsLinkedToCitizenPortal"" boolean NOT NULL DEFAULT false;
        RAISE NOTICE '✅ تم إضافة عمود IsLinkedToCitizenPortal';
    END IF;

    -- إضافة عمود LinkedById
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'Companies' AND column_name = 'LinkedById'
    ) THEN
        ALTER TABLE ""Companies"" 
        ADD COLUMN ""LinkedById"" uuid NULL;
        RAISE NOTICE '✅ تم إضافة عمود LinkedById';
    END IF;

    -- إضافة عمود LinkedToCitizenPortalAt
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'Companies' AND column_name = 'LinkedToCitizenPortalAt'
    ) THEN
        ALTER TABLE ""Companies"" 
        ADD COLUMN ""LinkedToCitizenPortalAt"" timestamp with time zone NULL;
        RAISE NOTICE '✅ تم إضافة عمود LinkedToCitizenPortalAt';
    END IF;

    -- تحديث سجل Migrations
    IF NOT EXISTS (
        SELECT 1 FROM ""__EFMigrationsHistory"" 
        WHERE ""MigrationId"" = '20260128032556_AddCitizenPortalLinkToCompany'
    ) THEN
        INSERT INTO ""__EFMigrationsHistory"" (""MigrationId"", ""ProductVersion"")
        VALUES ('20260128032556_AddCitizenPortalLinkToCompany', '9.0.0');
        RAISE NOTICE '✅ تم تسجيل Migration في التاريخ';
    END IF;
END $$;
";

    using var cmd = new NpgsqlCommand(sql, successfulConnection);
    cmd.ExecuteNonQuery();
    Console.WriteLine("\n✅ تم تطبيق Migration بنجاح!");

    Console.WriteLine("\n✅ تم تطبيق Migration بنجاح!");

    // عرض الأعمدة الجديدة
    var checkSql = @"
SELECT 
    column_name, 
    data_type, 
    is_nullable,
    column_default
FROM information_schema.columns 
WHERE table_name = 'Companies' 
    AND column_name IN ('IsLinkedToCitizenPortal', 'LinkedById', 'LinkedToCitizenPortalAt')
ORDER BY column_name;
";
    using var checkCmd = new NpgsqlCommand(checkSql, successfulConnection);
    using var reader = checkCmd.ExecuteReader();
    
    Console.WriteLine("\n📊 الأعمدة المضافة:");
    Console.WriteLine("----------------------------------------");
    while (reader.Read())
    {
        Console.WriteLine($"✓ {reader["column_name"]} - {reader["data_type"]} - Nullable: {reader["is_nullable"]}");
    }
    
    Console.WriteLine("\n🎉 تم تطبيق Migration بنجاح على قاعدة البيانات!");
}
catch (Exception ex)
{
    Console.WriteLine($"❌ خطأ: {ex.Message}");
    Console.WriteLine($"\nتفاصيل الخطأ:");
    Console.WriteLine(ex.ToString());
    Environment.Exit(1);
}
