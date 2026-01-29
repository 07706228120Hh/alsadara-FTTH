using System;
using Npgsql;

class Program
{
    static void Main()
    {
        var connectionString = "Host=72.61.183.61;Port=5432;Database=sadara_db;Username=sadara_user;Password=sadara_secure_password_2024;SSL Mode=Require;Trust Server Certificate=true";
        
        try
        {
            Console.WriteLine("🔌 جاري الاتصال بقاعدة البيانات...");
            using var conn = new NpgsqlConnection(connectionString);
            conn.Open();
            Console.WriteLine("✅ تم الاتصال بنجاح!");

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

            using var cmd = new NpgsqlCommand(sql, conn);
            cmd.ExecuteNonQuery();
            Console.WriteLine("✅ تم تطبيق Migration بنجاح!");

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
            using var checkCmd = new NpgsqlCommand(checkSql, conn);
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
            Console.WriteLine($"تفاصيل: {ex}");
            Environment.Exit(1);
        }
    }
}
