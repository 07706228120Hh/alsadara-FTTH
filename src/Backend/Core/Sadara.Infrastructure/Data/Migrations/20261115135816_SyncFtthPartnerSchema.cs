using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Sadara.Infrastructure.Data.Migrations
{
    /// <summary>
    /// Brings the EF model snapshot in line with schema that was applied to existing databases
    /// by hand (FTTH partners, excluded creators, partner/operator columns). Every statement is
    /// idempotent: on a database that already has the objects this migration changes nothing,
    /// on a fresh database it creates them.
    /// </summary>
    public partial class SyncFtthPartnerSchema : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("""
                ALTER TABLE "ZoneMaintenanceFees" ADD COLUMN IF NOT EXISTS "PartnerId" uuid;
                ALTER TABLE "TechnicianTransactions" ADD COLUMN IF NOT EXISTS "OperatorUsername" text;
                ALTER TABLE "TechnicianTransactions" ADD COLUMN IF NOT EXISTS "PartnerId" text;
                ALTER TABLE "SubscriptionLogs" ADD COLUMN IF NOT EXISTS "OperatorUsername" text;
                ALTER TABLE "FtthAccounts" ADD COLUMN IF NOT EXISTS "FtthMemberId" text;
                ALTER TABLE "FtthAccounts" ADD COLUMN IF NOT EXISTS "PartnerId" uuid;

                CREATE TABLE IF NOT EXISTS "FtthExcludedCreators" (
                    "Id" uuid NOT NULL,
                    "CompanyId" uuid NOT NULL,
                    "Identifier" text NOT NULL,
                    "Note" text,
                    "IsActive" boolean NOT NULL,
                    "CreatedById" uuid,
                    "CreatedAt" timestamp with time zone NOT NULL,
                    "UpdatedAt" timestamp with time zone,
                    "IsDeleted" boolean NOT NULL,
                    "DeletedAt" timestamp with time zone,
                    CONSTRAINT "PK_FtthExcludedCreators" PRIMARY KEY ("Id"),
                    CONSTRAINT "FK_FtthExcludedCreators_Companies_CompanyId" FOREIGN KEY ("CompanyId")
                        REFERENCES "Companies" ("Id") ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS "FtthPartners" (
                    "Id" uuid NOT NULL,
                    "CompanyId" uuid NOT NULL,
                    "Name" text NOT NULL,
                    "MainUsername" text NOT NULL,
                    "MainPasswordEncrypted" text NOT NULL,
                    "PartnerAccountId" text,
                    "ServerUrl" text NOT NULL,
                    "IsActive" boolean NOT NULL,
                    "Status" text,
                    "LastVerifiedAt" timestamp with time zone,
                    "CreatedAt" timestamp with time zone NOT NULL,
                    "UpdatedAt" timestamp with time zone,
                    "IsDeleted" boolean NOT NULL,
                    "DeletedAt" timestamp with time zone,
                    CONSTRAINT "PK_FtthPartners" PRIMARY KEY ("Id"),
                    CONSTRAINT "FK_FtthPartners_Companies_CompanyId" FOREIGN KEY ("CompanyId")
                        REFERENCES "Companies" ("Id") ON DELETE CASCADE
                );

                CREATE INDEX IF NOT EXISTS "IX_FtthAccounts_CompanyId_PartnerId"
                    ON "FtthAccounts" ("CompanyId", "PartnerId");
                CREATE UNIQUE INDEX IF NOT EXISTS "IX_FtthExcludedCreators_CompanyId_Identifier"
                    ON "FtthExcludedCreators" ("CompanyId", "Identifier") WHERE "IsDeleted" = false;
                CREATE UNIQUE INDEX IF NOT EXISTS "IX_FtthPartners_CompanyId_Name"
                    ON "FtthPartners" ("CompanyId", "Name") WHERE "IsDeleted" = false;
                CREATE INDEX IF NOT EXISTS "IX_FtthPartners_CompanyId_PartnerAccountId"
                    ON "FtthPartners" ("CompanyId", "PartnerAccountId");
                """);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            // Intentionally empty: these objects predate this migration on existing databases
            // and hold live data, so rolling the migration back must not drop them.
        }
    }
}
