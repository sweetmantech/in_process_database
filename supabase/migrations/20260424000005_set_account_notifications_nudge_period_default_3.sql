-- Align with create migration: new rows omitting nudge_period should default to 3 days.
ALTER TABLE public.account_notifications
ALTER COLUMN nudge_period
SET DEFAULT 3;
