-- Add id column as UUID primary key to in_process_message_moment table
ALTER TABLE "public"."in_process_message_moment"
ADD COLUMN "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID();

-- Add primary key constraint on id
ALTER TABLE "public"."in_process_message_moment"
ADD CONSTRAINT "in_process_message_moment_pkey" PRIMARY KEY ("id");
