-- LANGKAH 2 - PASANG database AWD (schema panel + pengaturan + aplikasi Toko + view Pelanggan).
-- Jalankan SETELAH 1_bersihkan_database.sql. Supabase: SQL Editor > New query > Run.

-- =====================================================================
-- BAGIAN A. Skema panel admin (supabase/schema.sql dari repositori awd-admin, tanpa perubahan)
-- =====================================================================
-- Arjawinangun Delivery – Skema database Supabase
-- Jalankan seluruh isi file ini di Supabase: SQL Editor > New query > Run.

-- 1) Tabel admin (siapa yang boleh masuk panel) -------------------------
create table if not exists public.admin (
  user_id uuid primary key references auth.users(id) on delete cascade,
  nama text not null,
  peran text not null check (peran in ('Admin Utama','Operator','Layanan Pelanggan')),
  dibuat_pada timestamptz not null default now()
);

-- 2) Tabel data. Kolom utama dipakai untuk filter/laporan,
--    detail lengkap disimpan di kolom "data" (jsonb).
create table if not exists public.pengguna (
  urut bigint generated always as identity,
  id text primary key,
  tipe text not null check (tipe in ('merchant','driver','customer')),
  nama text not null,
  status text,
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.produk (
  urut bigint generated always as identity,
  id text primary key,
  merchant_id text not null,
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.pesanan (
  urut bigint generated always as identity,
  id text primary key,
  status text,
  total integer,
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.versi_aplikasi (
  tipe text primary key check (tipe in ('merchant','driver','customer')),
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.spanduk (
  id integer primary key,
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.notifikasi (
  id integer primary key,
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.pesan_masuk (
  urut bigint generated always as identity,
  id text primary key,
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.pengaturan (
  kunci text primary key,
  data jsonb not null default '{}',
  diubah_pada timestamptz not null default now()
);
create table if not exists public.log_audit (
  id bigint generated always as identity primary key,
  admin_id uuid references auth.users(id) on delete set null,
  peran text,
  jam text,
  aksi text not null,
  waktu timestamptz not null default now()
);

create index if not exists produk_merchant_idx on public.produk(merchant_id);
create index if not exists pesanan_status_idx on public.pesanan(status);

-- 3) Penanda waktu ubah otomatis ---------------------------------------
create or replace function public.sentuh() returns trigger
language plpgsql as $$
begin new.diubah_pada = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array['pengguna','produk','pesanan','versi_aplikasi','spanduk','notifikasi','pesan_masuk','pengaturan'] loop
    execute format('drop trigger if exists sentuh on public.%I', t);
    execute format('create trigger sentuh before update on public.%I for each row execute function public.sentuh()', t);
  end loop;
end $$;

-- 4) Keamanan: Row Level Security (RLS) --------------------------------
-- Fungsi pembantu: peran admin yang sedang login (null bila bukan admin)
create or replace function public.peran_admin() returns text
language sql stable security definer set search_path = public as $$
  select peran from public.admin where user_id = auth.uid()
$$;
revoke all on function public.peran_admin() from public;
grant execute on function public.peran_admin() to authenticated;

alter table public.admin enable row level security;
drop policy if exists "admin baca diri sendiri" on public.admin;
create policy "admin baca diri sendiri" on public.admin
  for select to authenticated using (user_id = auth.uid());
-- Tidak ada kebijakan tulis: admin baru ditambahkan lewat SQL Editor (lihat README).

do $$
declare t text;
begin
  -- Tabel yang hanya boleh diubah Admin Utama & Operator
  foreach t in array array['pengguna','produk','pesanan','versi_aplikasi','spanduk','pengaturan'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "baca" on public.%I', t);
    execute format('drop policy if exists "tambah" on public.%I', t);
    execute format('drop policy if exists "ubah" on public.%I', t);
    execute format('drop policy if exists "hapus" on public.%I', t);
    execute format('create policy "baca" on public.%I for select to authenticated using (public.peran_admin() is not null)', t);
    execute format('create policy "tambah" on public.%I for insert to authenticated with check (public.peran_admin() in (''Admin Utama'',''Operator''))', t);
    execute format('create policy "ubah" on public.%I for update to authenticated using (public.peran_admin() in (''Admin Utama'',''Operator'')) with check (public.peran_admin() in (''Admin Utama'',''Operator''))', t);
    execute format('create policy "hapus" on public.%I for delete to authenticated using (public.peran_admin() = ''Admin Utama'')', t);
  end loop;
  -- Tabel yang boleh ditulis semua admin (balas pesan, notifikasi); hapus hanya Admin Utama
  foreach t in array array['notifikasi','pesan_masuk'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "baca" on public.%I', t);
    execute format('drop policy if exists "tambah" on public.%I', t);
    execute format('drop policy if exists "ubah" on public.%I', t);
    execute format('drop policy if exists "hapus" on public.%I', t);
    execute format('create policy "baca" on public.%I for select to authenticated using (public.peran_admin() is not null)', t);
    execute format('create policy "tambah" on public.%I for insert to authenticated with check (public.peran_admin() is not null)', t);
    execute format('create policy "ubah" on public.%I for update to authenticated using (public.peran_admin() is not null) with check (public.peran_admin() is not null)', t);
    execute format('create policy "hapus" on public.%I for delete to authenticated using (public.peran_admin() = ''Admin Utama'')', t);
  end loop;
end $$;

alter table public.log_audit enable row level security;
drop policy if exists "baca" on public.log_audit;
drop policy if exists "tambah" on public.log_audit;
create policy "baca" on public.log_audit for select to authenticated using (public.peran_admin() is not null);
create policy "tambah" on public.log_audit for insert to authenticated
  with check (public.peran_admin() is not null and admin_id = auth.uid());
-- Log audit tidak bisa diubah/dihapus dari klien (sengaja).

-- 5) Realtime untuk pesanan baru (notifikasi transaksi di panel) --------
do $$
begin
  alter publication supabase_realtime add table public.pesanan;
exception when duplicate_object then null;
end $$;

-- =====================================================================
-- BAGIAN B. Pengaturan Menu Layanan, Kategori Produk, Tampilan header, Hak akses menu
-- =====================================================================
insert into public.pengaturan (kunci, data) values
  ('layanan', '{"items": [{"id": "L1", "n": "AWD Food", "ic": "🍜", "img": "", "on": 1}, {"id": "L2", "n": "AWD Warung", "ic": "🏪", "img": "", "on": 1}, {"id": "L3", "n": "AWD Pasar & UMKM", "ic": "🥬", "img": "", "on": 1}, {"id": "L4", "n": "AWD Obat-obatan", "ic": "💊", "img": "", "on": 1}, {"id": "L5", "n": "AWD Kirim", "ic": "📦", "img": "", "on": 1}, {"id": "L6", "n": "AWD Pulsa & Data", "ic": "📱", "img": "", "on": 1}]}'::jsonb),
  ('kategori_produk', '{"items": [{"id": "K1", "n": "Makanan & Minuman Siap Saji", "ic": "🍱", "on": 1}, {"id": "K2", "n": "Makanan & Minuman Kemasan", "ic": "🥤", "on": 1}, {"id": "K3", "n": "Sembako", "ic": "🌾", "on": 1}, {"id": "K4", "n": "Kebutuhan Rumah Tangga", "ic": "🧴", "on": 1}, {"id": "K5", "n": "Kebutuhan Sehari-hari", "ic": "🛒", "on": 1}, {"id": "K6", "n": "Obat-obatan", "ic": "💊", "on": 1}, {"id": "K7", "n": "Lainnya", "ic": "📦", "on": 1}]}'::jsonb),
  ('tampilan_customer', '{"tpl": "gradien", "logo": "", "bg": "", "so": 1, "h": 170, "ls": 64, "lp": "kiri", "ns": 24, "nf": "bulat", "sr": 1, "nama": "Arjawinangun Delivery", "sl": "Cepat • Aman • Terpercaya", "c1": "#2563eb", "c2": "#0ea5e9", "nc": "#ffffff", "ph": "Cari warung, kategori, atau desa..."}'::jsonb),
  ('tampilan_merchant', '{"tpl": "gradien", "logo": "", "bg": "", "so": 1, "h": 150, "ls": 64, "lp": "kiri", "ns": 24, "nf": "bulat", "sr": 1, "nama": "AWD Mitra", "sl": "Kelola toko dan pesananmu", "c1": "#FFC400", "c2": "#FFA000", "nc": "#16130a", "ph": "Cari pesanan atau produk..."}'::jsonb),
  ('tampilan_driver', '{"tpl": "gradien", "logo": "", "bg": "", "so": 1, "h": 140, "ls": 64, "lp": "kiri", "ns": 24, "nf": "bulat", "sr": 0, "nama": "AWD Driver", "sl": "Antar cepat, aman, terpercaya", "c1": "#15803d", "c2": "#22c55e", "nc": "#ffffff", "ph": "Cari pesanan..."}'::jsonb)
on conflict (kunci) do nothing;

-- Aplikasi & website boleh MEMBACA kunci-kunci ini saja. Menulis tetap hanya Admin Utama & Operator.
drop policy if exists "baca publik konfigurasi" on public.pengaturan;
create policy "baca publik konfigurasi" on public.pengaturan
  for select to anon, authenticated
  using (kunci in ('layanan','kategori_produk','tampilan_customer','tampilan_merchant','tampilan_driver'));
grant select on public.pengaturan to anon, authenticated;

-- Hanya Admin Utama yang boleh mengubah hak akses menu
drop policy if exists "akses_menu tambah" on public.pengaturan;
drop policy if exists "akses_menu ubah" on public.pengaturan;
drop policy if exists "akses_menu hapus" on public.pengaturan;
create policy "akses_menu tambah" on public.pengaturan as restrictive for insert to authenticated
  with check (kunci <> 'akses_menu' or public.peran_admin() = 'Admin Utama');
create policy "akses_menu ubah" on public.pengaturan as restrictive for update to authenticated
  using (kunci <> 'akses_menu' or public.peran_admin() = 'Admin Utama')
  with check (kunci <> 'akses_menu' or public.peran_admin() = 'Admin Utama');
create policy "akses_menu hapus" on public.pengaturan as restrictive for delete to authenticated
  using (kunci <> 'akses_menu' or public.peran_admin() = 'Admin Utama');

-- Realtime: aplikasi memperbarui tampilan otomatis saat admin menyimpan
do $$ begin alter publication supabase_realtime add table public.pengaturan;
exception when duplicate_object then null; end $$;

-- =====================================================================
-- BAGIAN C. Aplikasi Toko (merchant)
-- Bentuk data mengikuti panel: pengguna.data = {id,t,name,sub,area,n,r,s,adr,hp,plate,jn,x},
-- produk.data = {id,n,k,h,st,on,kd,d,img,dc,dt,dv,dm}, pesanan.data = {id,c,m,d,s,p,...}.
-- Status toko di panel: Buka | Tutup | Ditangguhkan (toko baru mulai dari Ditangguhkan sampai admin mengaktifkan).
-- =====================================================================
alter table public.pengguna add column if not exists auth_id uuid unique references auth.users(id) on delete set null;

create or replace function public.merchant_saya() returns text
language sql stable security definer set search_path = public as $$
  select id from public.pengguna where auth_id = auth.uid() and tipe = 'merchant' and status in ('Buka','Tutup')
$$;
create or replace function public.merchant_nama() returns text
language sql stable security definer set search_path = public as $$
  select nama from public.pengguna where auth_id = auth.uid() and tipe = 'merchant' and status in ('Buka','Tutup')
$$;
revoke all on function public.merchant_saya(), public.merchant_nama() from public;
grant execute on function public.merchant_saya(), public.merchant_nama() to authenticated;

drop policy if exists "merchant baca diri sendiri" on public.pengguna;
create policy "merchant baca diri sendiri" on public.pengguna for select to authenticated using (auth_id = auth.uid());

drop policy if exists "merchant baca produk" on public.produk;
drop policy if exists "merchant tambah produk" on public.produk;
drop policy if exists "merchant ubah produk" on public.produk;
drop policy if exists "merchant hapus produk" on public.produk;
create policy "merchant baca produk" on public.produk for select to authenticated using (merchant_id = public.merchant_saya());
create policy "merchant tambah produk" on public.produk for insert to authenticated with check (merchant_id = public.merchant_saya());
create policy "merchant ubah produk" on public.produk for update to authenticated using (merchant_id = public.merchant_saya()) with check (merchant_id = public.merchant_saya());
create policy "merchant hapus produk" on public.produk for delete to authenticated using (merchant_id = public.merchant_saya());

-- Pesanan milik toko: dicocokkan lewat id toko (data.merchant_id) atau nama toko (data.m, seperti di panel)
drop policy if exists "merchant baca pesanan" on public.pesanan;
create policy "merchant baca pesanan" on public.pesanan for select to authenticated
  using ((data->>'merchant_id' = public.merchant_saya() or data->>'mid' = public.merchant_saya()) or data->>'m' = public.merchant_nama());

create or replace function public.daftar_merchant(p_nama text, p_hp text) returns void
language plpgsql security definer set search_path = public as $$
declare v_id text; v_email text;
begin
  if auth.uid() is null then raise exception 'Belum masuk'; end if;
  if exists (select 1 from public.pengguna where auth_id = auth.uid()) then return; end if;
  select email into v_email from auth.users where id = auth.uid();
  select 'M' || (coalesce(max(nullif(regexp_replace(id, '\D', '', 'g'), '')::bigint), 0) + 1) into v_id from public.pengguna;
  insert into public.pengguna (id, tipe, nama, status, data, auth_id) values (
    v_id, 'merchant', p_nama, 'Ditangguhkan',
    jsonb_build_object('id', v_id, 't', 'merchant', 'name', p_nama, 'sub', p_nama, 'area', '', 'n', 0, 'r', '0.0',
      's', 'Ditangguhkan', 'adr', '', 'hp', coalesce(p_hp, ''), 'plate', '', 'jn', to_char(now(), 'Mon YYYY'),
      'x', jsonb_build_object('email', coalesce(v_email, ''), 'login', 'Kata sandi', 'gps', '', 'kat', 'Makanan',
        'jam', '07.00-21.00', 'ktp', '', 'ktpf', '', 'bank', '', 'rek', '', 'an', '')),
    auth.uid());
end $$;

create or replace function public.toko_set_buka(p_buka boolean) returns void
language sql security definer set search_path = public as $$
  update public.pengguna
     set status = case when p_buka then 'Buka' else 'Tutup' end,
         data = data || jsonb_build_object('s', case when p_buka then 'Buka' else 'Tutup' end)
   where auth_id = auth.uid() and tipe = 'merchant' and status in ('Buka','Tutup')
$$;

-- Alur status pesanan di panel: Baru -> Diproses -> Diantar -> Selesai (Dibatalkan).
create or replace function public.toko_ubah_status(p_id text, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.pesanan set status = p_status, data = data || jsonb_build_object('s', p_status)
   where id = p_id
     and ((data->>'merchant_id' = public.merchant_saya() or data->>'mid' = public.merchant_saya()) or data->>'m' = public.merchant_nama())
     and ((p_status = 'Diproses' and status = 'Baru') or (p_status = 'Dibatalkan' and status in ('Baru','Diproses')));
  if not found then raise exception 'Pesanan tidak ditemukan atau status tidak bisa diubah'; end if;
end $$;

create or replace function public.toko_pesanan_siap(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.pesanan set data = data || jsonb_build_object('siap', 1)
   where id = p_id and status = 'Diproses'
     and ((data->>'merchant_id' = public.merchant_saya() or data->>'mid' = public.merchant_saya()) or data->>'m' = public.merchant_nama());
  if not found then raise exception 'Pesanan tidak ditemukan'; end if;
end $$;

revoke all on function public.daftar_merchant(text,text), public.toko_set_buka(boolean),
  public.toko_ubah_status(text,text), public.toko_pesanan_siap(text) from public;
grant execute on function public.daftar_merchant(text,text), public.toko_set_buka(boolean),
  public.toko_ubah_status(text,text), public.toko_pesanan_siap(text) to authenticated;

-- =====================================================================
-- BAGIAN D. Aplikasi Pelanggan (AWD Pelanggan v5): view baca-saja + fungsi daftar/pesan/riwayat/lacak + ulasan
-- (dari awd-supabase-sesuaikan-panel.sql, disesuaikan: diskon produk dan skema tabel panel)
-- =====================================================================
-- =====================================================================
--  AWD Pelanggan <-> Panel Admin AWD  (menyesuaikan database yang SUDAH ADA)
--  Tabel panel yang dipakai apa adanya: pengguna, produk, pesanan,
--  spanduk, versi_aplikasi, pengaturan, admin  (kolom: id, ..., data jsonb, urut).
--  Skrip ini TIDAK mengubah tabel-tabel itu. Yang ditambahkan:
--    - view baca-saja untuk aplikasi pelanggan (awd_toko, awd_produk, ...)
--    - fungsi (RPC) untuk daftar, simpan alamat, buat pesanan, riwayat, lacak
--    - tabel baru "ulasan"
--  Aman dijalankan ulang. Jalankan di Supabase > SQL Editor.
-- =====================================================================

create or replace function awd_int(t text) returns int language sql immutable
  as $$ select case when t ~ '^[0-9]{1,9}$' then t::int end $$;

create or replace function awd_is_admin() returns boolean language sql security definer stable set search_path = public
  as $$ select exists (select 1 from admin where user_id = auth.uid()) $$;

-- ---------- 1) View untuk aplikasi pelanggan (hanya kolom yang aman) ----------
create or replace view awd_toko as
select p.id, p.nama, p.status,
       p.data->>'adr'  as alamat,  p.data->>'area' as wilayah,  p.data->>'logo' as foto,
       p.data->>'r'    as rating,
       p.data->'x'->>'kat'  as kategori,   -- Kategori usaha
       p.data->'x'->>'lay'  as layanan,    -- Layanan di aplikasi pelanggan (nama layanan)
       p.data->'x'->>'desc' as deskripsi,  -- Keterangan toko
       awd_int(p.data->'x'->>'fee') as ongkir,
       awd_int(p.data->'x'->>'eta') as eta,
       p.urut
from pengguna p
where p.tipe = 'merchant' and lower(p.status) = 'buka';

create or replace view awd_produk as
select pr.id, pr.merchant_id,
       pr.data->>'n' as nama, pr.data->>'k' as kategori,
       awd_int(pr.data->>'h') as harga, awd_int(pr.data->>'st') as stok,
       pr.data->>'img' as img, pr.data->>'d' as d, pr.urut,
       coalesce(awd_int(pr.data->>'dc'),0) as dc, pr.data->>'dt' as dt,
       coalesce(awd_int(pr.data->>'dv'),0) as dv, coalesce(awd_int(pr.data->>'dm'),0) as dm
from produk pr join awd_toko t on t.id = pr.merchant_id
where coalesce(pr.data->>'on','1') in ('1','true') and coalesce(awd_int(pr.data->>'st'),0) > 0;

create or replace view awd_spanduk as
select s.id, s.data->>'n' as judul, s.data->>'ds' as ds, s.data->>'img' as img, s.data->>'link' as link
from spanduk s
where coalesce(s.data->>'on','1') in ('1','true')
  and (coalesce(s.data->>'st','') = '' or (s.data->>'st') <= to_char(current_date,'YYYY-MM-DD'))
  and (coalesce(s.data->>'en','') = '' or (s.data->>'en') >= to_char(current_date,'YYYY-MM-DD'))
order by s.id;

create or replace view awd_versi as select v.data from versi_aplikasi v where v.tipe = 'customer';
create or replace view awd_pengaturan as select g.kunci, g.data from pengaturan g where g.kunci in ('layanan','tampilan_customer');

grant select on awd_toko, awd_produk, awd_spanduk, awd_versi, awd_pengaturan to anon, authenticated;

-- ---------- 2) Fungsi untuk pelanggan (SECURITY DEFINER, wajib login) ----------
create sequence if not exists awd_seq_cust;
create sequence if not exists awd_seq_pesanan;
do $s$ declare m int; begin
  select coalesce(max(awd_int(substring(id from 5))), 2400) into m from pesanan where id ~ '^ORD-[0-9]+$';
  perform setval('awd_seq_pesanan', greatest(m, 2400));
end $s$;

create or replace function awd_daftar(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); nid text; d jsonb; bln text[] := array['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
begin
  if u is null then raise exception 'Harus masuk dulu'; end if;
  select data into d from pengguna where tipe='customer' and data->'x'->>'uid' = u::text limit 1;
  if d is not null then return d; end if;
  if coalesce(p->>'hp','') !~ '^08[0-9]{8,12}$' then raise exception 'Nomor HP tidak valid'; end if;
  if coalesce(trim(p->>'nama'),'') = '' then raise exception 'Nama wajib diisi'; end if;
  if exists (select 1 from pengguna where tipe='customer' and regexp_replace(data->>'hp','[^0-9]','','g') = p->>'hp') then
    raise exception 'Nomor sudah terdaftar'; end if;
  nid := 'CA' || nextval('awd_seq_cust');
  d := jsonb_build_object('id',nid,'t','customer','name',trim(p->>'nama'),'sub',p->>'hp','area','','n',0,'r','5.0','s','Aktif',
        'adr','','hp',p->>'hp','plate','','jn', bln[extract(month from now())::int] || ' ' || extract(year from now())::int,
        'x', jsonb_build_object('email',coalesce(p->>'email',''),'login','Kata sandi','gps','','pay','COD (bayar di tempat)','uid',u::text),
        'photo', coalesce(p->>'foto',''), 'alamat','[]'::jsonb);
  insert into pengguna(id,tipe,nama,status,data) values (nid,'customer',trim(p->>'nama'),'Aktif',d);
  return d;
end $$;

create or replace function awd_profil() returns jsonb language sql security definer stable set search_path = public as $$
  select data from pengguna where tipe='customer' and data->'x'->>'uid' = auth.uid()::text limit 1 $$;

create or replace function awd_simpan_alamat(a jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or jsonb_typeof(a) <> 'array' or jsonb_array_length(a) > 10 then raise exception 'Data alamat tidak valid'; end if;
  update pengguna set data = (data || jsonb_build_object('alamat',a,'adr',coalesce(a->0->>'street',''),'area',coalesce(a->0->>'desa','')))
        || jsonb_build_object('x', (data->'x') || jsonb_build_object('gps', coalesce(a->0->>'lat','') || ', ' || coalesce(a->0->>'lng','')))
  where tipe='customer' and data->'x'->>'uid' = auth.uid()::text;
end $$;

create or replace function awd_pesan(p jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare u uuid := auth.uid(); c pengguna%rowtype; t awd_toko%rowtype; pr awd_produk%rowtype; it jsonb;
  lay text := coalesce(p->>'layanan','order'); sub int := 0; fee int := 0; sf int := 0; q int; per int; lst jsonb := '[]'::jsonb;
  oid text; d jsonb; tot int; mname text; mid text := null; amt int;
begin
  if u is null then raise exception 'Harus masuk dulu'; end if;
  select * into c from pengguna where tipe='customer' and data->'x'->>'uid' = u::text limit 1;
  if not found then raise exception 'Akun pelanggan tidak ditemukan'; end if;
  if lower(c.status) <> 'aktif' then raise exception 'Akun belum aktif atau diblokir'; end if;
  if lay = 'order' then
    select * into t from awd_toko where id = p->>'merchant_id';
    if not found then raise exception 'Toko tidak tersedia'; end if;
    fee := coalesce(t.ongkir,5000); sf := 1500; mname := t.nama; mid := t.id;
    for it in select * from jsonb_array_elements(coalesce(p->'items','[]'::jsonb)) loop
      q := greatest(1, least(50, coalesce(awd_int(it->>'qty'),1)));
      select * into pr from awd_produk where id = it->>'produk_id' and merchant_id = t.id;
      if not found then raise exception 'Produk tidak tersedia'; end if;
      if pr.stok < q then raise exception 'Stok % tidak cukup', pr.nama; end if;
      -- Diskon produk (panel/Aplikasi Toko): berlaku bila jumlah dibeli >= Minimal Jumlah Pembelian (pcs)
      per := 0;
      if pr.dc = 1 and pr.dv > 0 and q >= pr.dm then
        if pr.dt = 'Rp' then per := least(pr.dv, pr.harga);
        else per := round(pr.harga * least(pr.dv, 100) / 100.0)::int; end if;
      end if;
      sub := sub + (pr.harga - per) * q;
      lst := lst || jsonb_build_object('id',pr.id,'n',pr.nama,'h',pr.harga - per,'h0',pr.harga,'q',q);
      update produk set data = jsonb_set(data,'{st}', to_jsonb(greatest(0, coalesce(awd_int(data->>'st'),0) - q))) where id = pr.id;
    end loop;
    if jsonb_array_length(lst) = 0 then raise exception 'Keranjang kosong'; end if;
  elsif lay in ('kirim','pulsa') then
    amt := awd_int(p->>'total');
    if amt is null or amt < 1000 or amt > 1000000 then raise exception 'Nominal tidak valid'; end if;
    mname := left(coalesce(p->>'nama', case when lay='kirim' then 'AWD Kirim' else 'AWD Pulsa & Data' end),80);
    if lay = 'kirim' then fee := amt; else sub := amt; end if;
    lst := jsonb_build_array(jsonb_build_object('n',mname,'h',amt,'q',1));
  else raise exception 'Layanan tidak dikenal'; end if;
  tot := sub + fee + sf; oid := 'ORD-' || nextval('awd_seq_pesanan');
  d := jsonb_build_object('id',oid,'c',c.nama,'m',mname,'d','','s','Baru','p',tot,'cid',u::text,'cust',c.id,'mid',mid,'svc',lay,
        'items',lst,'sub',sub,'fee',fee,'sf',sf,'pay',coalesce(p->>'metode','cod'),'adr',coalesce(p->'alamat','{}'::jsonb),
        'note',left(coalesce(p->>'catatan',''),200),'at',to_char(now() at time zone 'Asia/Jakarta','YYYY-MM-DD"T"HH24:MI'));
  insert into pesanan(id,status,total,data) values (oid,'Baru',tot,d);
  return d;
end $$;

create or replace function awd_pesanan_saya() returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce(jsonb_agg(x.data order by x.urut desc),'[]'::jsonb)
  from (select data, urut from pesanan where data->>'cid' = auth.uid()::text order by urut desc limit 50) x $$;

-- Titik lokasi "lat, lng" (teks di panel) -> {lat,lng}; null bila tidak valid
create or replace function awd_ll(t text) returns jsonb language sql immutable as $$
  select case when t ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?\s*$'
    then jsonb_build_object('lat', split_part(t, ',', 1)::numeric, 'lng', trim(split_part(t, ',', 2))::numeric) end $$;

-- Pelacakan: status, nama driver, dan titik lokasi driver / toko / tujuan untuk peta di aplikasi
create or replace function awd_lacak(pid text) returns jsonb language sql security definer stable set search_path = public as $$
  select jsonb_build_object('s', o.data->>'s', 'd', coalesce(o.data->>'d',''),
    'drv',  (select awd_ll(p.data->'x'->>'gps') from pengguna p where p.tipe = 'driver' and p.nama = o.data->>'d' limit 1),
    'toko', (select awd_ll(p.data->'x'->>'gps') from pengguna p where p.id = o.data->>'mid'),
    'tujuan', case when (o.data->'adr'->>'lat') ~ '^-?[0-9.]+$' and (o.data->'adr'->>'lng') ~ '^-?[0-9.]+$'
      then jsonb_build_object('lat', (o.data->'adr'->>'lat')::numeric, 'lng', (o.data->'adr'->>'lng')::numeric) end)
  from pesanan o where o.id = pid and o.data->>'cid' = auth.uid()::text $$;

revoke all on function awd_daftar(jsonb), awd_profil(), awd_simpan_alamat(jsonb), awd_pesan(jsonb), awd_pesanan_saya(), awd_lacak(text) from public, anon;
grant execute on function awd_daftar(jsonb), awd_profil(), awd_simpan_alamat(jsonb), awd_pesan(jsonb), awd_pesanan_saya(), awd_lacak(text) to authenticated;

-- ---------- 3) Ulasan (belum ada di panel) ----------
create table if not exists ulasan (
  id bigint generated always as identity primary key,
  pengguna_uid uuid not null default auth.uid(),
  produk_id text, pesanan_id text, nama_pengulas text,
  bintang int not null check (bintang between 1 and 5), komentar text,
  dibuat_pada timestamptz not null default now());
alter table ulasan enable row level security;
drop policy if exists p_ulasan_baca on ulasan;  create policy p_ulasan_baca on ulasan for select using (true);
drop policy if exists p_ulasan_tulis on ulasan; create policy p_ulasan_tulis on ulasan for insert to authenticated with check (pengguna_uid = auth.uid());
drop policy if exists p_ulasan_adm on ulasan;   create policy p_ulasan_adm on ulasan for delete using (awd_is_admin());

-- ---------- 4) Pemeriksaan keamanan (jalankan terpisah, lihat hasilnya) ----------
-- Pelanggan login memakai Supabase Auth yang sama dengan admin, sehingga role "authenticated" juga
-- dimiliki pelanggan. Pastikan TIDAK ADA policy tabel panel yang hanya memeriksa "authenticated":
--   select tablename, policyname, roles, cmd, qual, with_check from pg_policies where schemaname = 'public' order by 1;
-- Policy tabel panel harus memeriksa tabel admin, misalnya:  exists (select 1 from admin where user_id = auth.uid())

-- ---------- 4) Notifikasi (lonceng): pengumuman/promo dari panel (Notifikasi & Pesan) ----------
create or replace view awd_notif as
select n.id, n.data->>'ti' as judul, n.data->>'tm' as waktu, n.data->>'to' as untuk
from notifikasi n where n.data->>'to' in ('Semua pengguna','Pelanggan');
grant select on awd_notif to anon, authenticated;

-- ---------- 5) Chat pelanggan <-> toko ----------
create table if not exists chat_toko (
  id bigint generated always as identity primary key,
  merchant_id text not null,
  cust_uid uuid not null,
  cust_nama text,
  dari text not null check (dari in ('pelanggan','toko')),
  isi text not null check (length(isi) between 1 and 500),
  dibaca boolean not null default false,
  dibuat_pada timestamptz not null default now());
create index if not exists chat_toko_idx on chat_toko (merchant_id, cust_uid, id);
alter table chat_toko enable row level security;
drop policy if exists chat_admin_baca on chat_toko;      create policy chat_admin_baca on chat_toko for select to authenticated using (public.peran_admin() is not null);
drop policy if exists chat_pelanggan_baca on chat_toko;  create policy chat_pelanggan_baca on chat_toko for select to authenticated using (cust_uid = auth.uid());
drop policy if exists chat_toko_baca on chat_toko;       create policy chat_toko_baca on chat_toko for select to authenticated using (merchant_id = public.merchant_saya());
-- Menulis hanya lewat fungsi di bawah (tidak ada kebijakan insert/update langsung).
do $$ begin alter publication supabase_realtime add table public.chat_toko;
exception when duplicate_object then null; end $$;

create or replace function awd_chat_kirim(p_merchant text, p_isi text) returns void language plpgsql security definer set search_path = public as $$
declare v_nama text;
begin
  if auth.uid() is null then raise exception 'Harus masuk dulu'; end if;
  if coalesce(trim(p_isi),'') = '' then raise exception 'Pesan kosong'; end if;
  if not exists (select 1 from awd_toko where id = p_merchant) then raise exception 'Toko tidak ditemukan'; end if;
  select nama into v_nama from pengguna where tipe = 'customer' and data->'x'->>'uid' = auth.uid()::text limit 1;
  insert into chat_toko (merchant_id, cust_uid, cust_nama, dari, isi)
  values (p_merchant, auth.uid(), coalesce(v_nama,'Pelanggan'), 'pelanggan', left(trim(p_isi), 500));
end $$;

create or replace function awd_chat_baca(p_merchant text) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update chat_toko set dibaca = true where merchant_id = p_merchant and cust_uid = auth.uid() and dari = 'toko' and not dibaca;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'dari', dari, 'isi', isi,
            'at', to_char(dibuat_pada at time zone 'Asia/Jakarta', 'HH24:MI')) order by id)
          from (select * from chat_toko where merchant_id = p_merchant and cust_uid = auth.uid() order by id desc limit 100) x), '[]'::jsonb);
end $$;

create or replace function awd_chat_daftar() returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce(jsonb_agg(t.x order by (t.x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('mid', c.merchant_id, 'nama', coalesce((select nama from pengguna where id = c.merchant_id), 'Toko'),
             'isi', c.isi, 'dari', c.dari, 'id', c.id,
             'belum', (select count(*) from chat_toko z where z.merchant_id = c.merchant_id and z.cust_uid = auth.uid() and z.dari = 'toko' and not z.dibaca)) as x
    from chat_toko c
    where c.id in (select max(id) from chat_toko where cust_uid = auth.uid() group by merchant_id)) t $$;

-- Sisi toko (Aplikasi Toko)
create or replace function toko_chat_daftar() returns jsonb language sql security definer stable set search_path = public as $$
  select coalesce(jsonb_agg(t.x order by (t.x->>'id')::bigint desc), '[]'::jsonb) from (
    select jsonb_build_object('cust', c.cust_uid, 'nama', coalesce(c.cust_nama,'Pelanggan'), 'isi', c.isi, 'dari', c.dari, 'id', c.id,
             'belum', (select count(*) from chat_toko z where z.merchant_id = c.merchant_id and z.cust_uid = c.cust_uid and z.dari = 'pelanggan' and not z.dibaca)) as x
    from chat_toko c
    where c.merchant_id = public.merchant_saya()
      and c.id in (select max(id) from chat_toko where merchant_id = public.merchant_saya() group by cust_uid)) t $$;

create or replace function toko_chat_baca(p_cust uuid) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if public.merchant_saya() is null then raise exception 'Toko belum aktif'; end if;
  update chat_toko set dibaca = true where merchant_id = public.merchant_saya() and cust_uid = p_cust and dari = 'pelanggan' and not dibaca;
  return coalesce((select jsonb_agg(jsonb_build_object('id', id, 'dari', dari, 'isi', isi,
            'at', to_char(dibuat_pada at time zone 'Asia/Jakarta', 'HH24:MI')) order by id)
          from (select * from chat_toko where merchant_id = public.merchant_saya() and cust_uid = p_cust order by id desc limit 100) x), '[]'::jsonb);
end $$;

create or replace function toko_chat_kirim(p_cust uuid, p_isi text) returns void language plpgsql security definer set search_path = public as $$
begin
  if public.merchant_saya() is null then raise exception 'Toko belum aktif'; end if;
  if coalesce(trim(p_isi),'') = '' then raise exception 'Pesan kosong'; end if;
  if not exists (select 1 from chat_toko where merchant_id = public.merchant_saya() and cust_uid = p_cust) then
    raise exception 'Percakapan tidak ditemukan'; end if;
  insert into chat_toko (merchant_id, cust_uid, cust_nama, dari, isi)
  values (public.merchant_saya(), p_cust,
          (select cust_nama from chat_toko where merchant_id = public.merchant_saya() and cust_uid = p_cust limit 1),
          'toko', left(trim(p_isi), 500));
end $$;

revoke all on function awd_chat_kirim(text,text), awd_chat_baca(text), awd_chat_daftar(),
  toko_chat_daftar(), toko_chat_baca(uuid), toko_chat_kirim(uuid,text) from public, anon;
grant execute on function awd_chat_kirim(text,text), awd_chat_baca(text), awd_chat_daftar(),
  toko_chat_daftar(), toko_chat_baca(uuid), toko_chat_kirim(uuid,text) to authenticated;
