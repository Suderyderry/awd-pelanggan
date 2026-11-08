-- LANGKAH 1 - BERSIHKAN database (menghapus SEMUA tabel, view, dan fungsi di schema public).
-- Akun login (Authentication > Users) TIDAK terhapus. Jalankan sekali, lalu lanjut ke 2_pasang_database.sql.
-- PERINGATAN: seluruh data di tabel akan hilang. Hanya untuk tahap uji coba.
do $$
declare r record;
begin
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('v','m')
             and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e') loop
    execute format('drop view if exists public.%I cascade', r.relname);
    execute format('drop materialized view if exists public.%I cascade', r.relname);
  end loop;
  for r in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind in ('r','p')
             and not exists (select 1 from pg_depend d where d.objid = c.oid and d.deptype = 'e') loop
    execute format('drop table if exists public.%I cascade', r.relname);
  end loop;
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.prokind = 'f'
             and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') loop
    execute format('drop function if exists %s cascade', r.f);
  end loop;
end $$;
