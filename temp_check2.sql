-- Check ReceivedBy columns
SELECT column_name FROM information_schema.columns WHERE table_name='TechnicianCollections' AND column_name LIKE 'Received%' ORDER BY 1;
SELECT column_name FROM information_schema.columns WHERE table_name='TechnicianTransactions' AND column_name LIKE 'Received%' ORDER BY 1;
-- Check RenewalCycle columns
SELECT column_name FROM information_schema.columns WHERE table_name='CitizenSubscriptions' AND column_name IN ('RenewalCycleMonths','AutoRenew','NextRenewalDate','LastRenewalDate') ORDER BY 1;
-- Check Departments table
SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name='Departments';
-- Check AttendanceRecords columns
SELECT column_name FROM information_schema.columns WHERE table_name='AttendanceRecords' AND column_name IN ('Status','LateMinutes','WorkedMinutes','OvertimeMinutes','EarlyDepartureMinutes','ExpectedStartTime','ExpectedEndTime','WorkScheduleId','DeviceFingerprint','ServerValidatedLocation','DistanceFromCenter','AuditUserId') ORDER BY 1;
