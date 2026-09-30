# Changelog

Semua perubahan penting pada proyek ini dicatat di file ini.

## v1 Beta R1 — 2026-09-29

### Diubah

- Menetapkan baseline evidence-grounded: current-price ATR trailing, `ATRShift=1`, `ATRMultiplier=1.0`, aktivasi OFF, dan minimum trailing step OFF.
- Memisahkan `ANCHOR_CURRENT_PRICE` (baseline) dari `ANCHOR_FAVORABLE_EXTREME` (eksperimen).
- Mengganti aktivasi boolean menjadi mode OFF, ATR, atau points; ATR activation dihitung ulang memakai ATR shifted hingga terpicu.
- Menambahkan filter arah posisi dan filter komentar substring case-sensitive.
- Menjadikan persistensi extrema terbatas pada mode favorable-extreme; baseline tetap aman sesudah restart melalui SL broker yang sudah ada.
- Menambahkan diagnostik izin terminal/program/account/symbol sebelum permintaan modifikasi.
- Memperluas log dengan mode, ATR shift, anchor, tick size, point, alasan keputusan, kode `STATE_RESTORED_CANDIDATE_INVALID`, serta detail rejection retcode.
- Memisahkan throttle interval menjadi `SKIP_MODIFICATION_INTERVAL` agar metrik `SKIP_MIN_STEP` tidak tercampur.
- Menambahkan validasi rentang enum input dan matriks 50 skenario uji wajib beserta release gate.
- Menyinkronkan cache SL untuk ticket terkait pada `OnTradeTransaction()` dan mencatat hasil lokal `OrderSend()` pada log sukses.

### Dijaga

- Tidak ada entry, close, volume change, TP mutation, pip fixed logic, ataupun modifikasi per-symbol sebagai pengganti ticket.
- Semua perubahan SL memakai `TRADE_ACTION_SLTP`, ticket `ulong`, TP saat ini, validasi tick/stop/freeze, dan pemeriksaan retcode server.

### Validasi tertunda

- Compile MetaEditor F7 dan pengujian Strategy Tester/HFM Demo harus dijalankan pada Windows/MT5 karena toolchain MQL5 tidak tersedia di lingkungan Linux pengembangan ini.
