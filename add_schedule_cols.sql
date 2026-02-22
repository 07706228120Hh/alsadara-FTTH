-- Add work schedule fields to Users table (hybrid schedule system)
-- WorkScheduleId: link to a schedule (priority 2)
-- CustomWorkStartTime/EndTime: custom per-employee time (priority 1)

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'Users' AND column_name = 'WorkScheduleId') THEN
        ALTER TABLE "Users" ADD COLUMN "WorkScheduleId" integer NULL;
        RAISE NOTICE 'Added WorkScheduleId column';
    ELSE
        RAISE NOTICE 'WorkScheduleId already exists';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'Users' AND column_name = 'CustomWorkStartTime') THEN
        ALTER TABLE "Users" ADD COLUMN "CustomWorkStartTime" time NULL;
        RAISE NOTICE 'Added CustomWorkStartTime column';
    ELSE
        RAISE NOTICE 'CustomWorkStartTime already exists';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'Users' AND column_name = 'CustomWorkEndTime') THEN
        ALTER TABLE "Users" ADD COLUMN "CustomWorkEndTime" time NULL;
        RAISE NOTICE 'Added CustomWorkEndTime column';
    ELSE
        RAISE NOTICE 'CustomWorkEndTime already exists';
    END IF;
END $$;
