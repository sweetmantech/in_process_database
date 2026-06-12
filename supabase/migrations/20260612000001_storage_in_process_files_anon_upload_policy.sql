CREATE POLICY "Allow anon uploads" ON storage.objects FOR insert TO anon
WITH
  CHECK (bucket_id = 'in_process_files');
