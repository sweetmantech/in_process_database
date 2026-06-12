create policy "Allow anon uploads"
on storage.objects for insert
to anon
with check (bucket_id = 'in_process_files');
