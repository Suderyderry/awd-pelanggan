# AWD Pelanggan (Android)

Aplikasi pelanggan Arjawinangun Delivery. Satu file web (`www/index.html`) dibungkus Capacitor menjadi APK
lewat GitHub Actions. Terhubung ke Supabase dan panel admin AWD (https://suderyderry.github.io/awd-admin/).

## Diatur dari panel admin (tanpa ubah kode)
- Header (logo, nama, slogan, warna, tinggi, font, kolom pencarian) : Kelola Aplikasi Android > Aplikasi Pelanggan > Tampilan
- Kotak "Pilih Layanan" : Kelola Aplikasi Android > Menu Layanan
- Toko (layanan, keterangan, ongkir, estimasi), produk, harga, stok, diskon : Data Toko
- Banner : Manajemen Konten; pemeliharaan dan fitur : Kontrol versi
- Pesanan dan statusnya : Transaksi & Pesanan

## Fitur aplikasi
- Ikon layanan dari panel tampil penuh (teks disembunyikan bila memakai gambar); banner tampil utuh sesuai rasio gambar.
- Lonceng notifikasi: pengumuman/promo dari panel, status pesanan (diproses, diantar, sudah sampai), dan pesan baru dari toko.
  Notifikasi diperiksa tiap 20 detik saat aplikasi terbuka (belum berupa push saat aplikasi tertutup).
- Halaman toko: kategori layanan, filter kategori produk, dan tombol Chat dengan Toko (tersambung ke Aplikasi Toko).
- Aktivitas: peta lokasi toko, tujuan, dan driver untuk pesanan yang sedang berjalan (lokasi driver dibaca dari kolom GPS driver di panel).

## Diskon produk
Berlaku bila jumlah dibeli >= Minimal Jumlah Pembelian (pcs). Dihitung di database (`awd_pesan`).

## Langkah
1. Supabase > SQL Editor: jalankan `supabase/1_bersihkan_database.sql` (jika mengulang) lalu `supabase/2_pasang_database.sql`.
2. Supabase > Authentication > Providers > Email: Allow new users to sign up = ON, Confirm email = OFF.
3. Unggah isi folder ini ke repositori GitHub (termasuk folder `.github`), lalu buka Actions > Build APK Android.
4. Unduh artifact `awd-pelanggan-apk`, pasang `app-debug.apk`.

URL dan Publishable key Supabase tertanam di `www/index.html` (konstanta `AWD_CFG`). Kunci itu memang publik;
data dilindungi RLS. Jangan pernah memasukkan Secret/service_role key.
