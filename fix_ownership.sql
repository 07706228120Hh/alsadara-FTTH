-- Fix ownership of tables owned by postgres
ALTER TABLE "AttendanceRecords" OWNER TO sadara_user;
ALTER TABLE "ISPSubscribers" OWNER TO sadara_user;
ALTER TABLE "SubscriptionLogs" OWNER TO sadara_user;
ALTER TABLE "ZoneStatistics" OWNER TO sadara_user;
