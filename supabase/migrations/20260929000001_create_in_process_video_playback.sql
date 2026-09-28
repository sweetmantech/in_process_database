-- Streaming playback copy of a moment's video (Mux today). Arweave stays the
-- permanent copy referenced on-chain; this table maps a moment to its playback
-- asset so the provider can change without touching token metadata.
CREATE TABLE "public"."in_process_video_playback" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "moment" UUID NOT NULL,
  "provider" TEXT NOT NULL DEFAULT 'mux',
  "asset_id" TEXT,
  "playback_id" TEXT,
  "status" TEXT NOT NULL DEFAULT 'preparing',
  "source_uri" TEXT,
  "last_viewed_at" TIMESTAMPTZ,
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_video_playback" enable ROW level security;

CREATE UNIQUE INDEX in_process_video_playback_pkey ON public.in_process_video_playback USING btree (id);

ALTER TABLE "public"."in_process_video_playback"
ADD CONSTRAINT "in_process_video_playback_pkey" PRIMARY KEY USING index "in_process_video_playback_pkey";

ALTER TABLE "public"."in_process_video_playback"
ADD CONSTRAINT "in_process_video_playback_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE "public"."in_process_video_playback"
ADD CONSTRAINT "in_process_video_playback_status_check" CHECK (status IN ('preparing', 'ready', 'errored'));

-- One playback asset per moment; also serves build_moment_json's lookup by moment.
CREATE UNIQUE INDEX in_process_video_playback_moment_unique ON public.in_process_video_playback USING btree (moment);

ALTER TABLE "public"."in_process_video_playback"
ADD CONSTRAINT "in_process_video_playback_moment_unique" UNIQUE USING index "in_process_video_playback_moment_unique";

-- Provider webhooks (e.g. Mux video.asset.ready) identify rows by asset id.
CREATE UNIQUE INDEX in_process_video_playback_provider_asset_unique ON public.in_process_video_playback USING btree (provider, asset_id)
WHERE
  asset_id IS NOT NULL;
