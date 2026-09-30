# ATR Trailing Stop Manager EA v1 Beta R1

Expert Advisor (EA) MetaTrader 5 untuk riset, Strategy Tester, dan forward test akun demo. EA ini **hanya** mengelola Stop Loss (SL) posisi yang sudah terbuka. EA tidak membuka posisi, tidak mengubah volume, tidak menutup posisi, dan tidak mengubah Take Profit (TP).

> Bukan rekomendasi penggunaan live-money maupun klaim profitabilitas.

## Deliverable

- `ATR_Trailing_Manager_v1_Beta_R1.mq5` — EA produksi sesuai PRD R1.
- `tests/ATR_Trailing_TestHarness.mq5` — EA terpisah yang membuka satu posisi deterministik, hanya di Strategy Tester.
- `TEST_MATRIX.md` — prosedur dan bukti uji yang harus dicatat.
- `CHANGELOG.md` — riwayat perubahan R1.
- `ATR_Trailing_Manager_v1_Beta.mq5` — implementasi pra-R1 yang dipertahankan hanya sebagai referensi historis; jangan gunakan untuk validasi R1.

## Instalasi dan kompilasi

1. Di MT5 pilih **File → Open Data Folder**.
2. Salin `ATR_Trailing_Manager_v1_Beta_R1.mq5` ke `MQL5/Experts/`.
3. Salin `tests/ATR_Trailing_TestHarness.mq5` ke `MQL5/Experts/tests/`.
4. Buka kedua file melalui MetaEditor dan compile dengan **F7**.
5. Pastikan tidak ada error/warning yang tidak dapat dijelaskan, lalu attach manager R1 ke chart target.

Tidak ada DLL, file eksternal, web request, Python, ataupun custom indicator. ATR menggunakan indikator native MT5.

## Baseline versus eksperimen

### Baseline default — kondisi pembanding

| Input | Nilai | Makna |
|---|---:|---|
| `ATRPeriod` | `14` | Periode ATR native. |
| `ATRTimeframe` | `PERIOD_CURRENT` | Timeframe chart untuk ATR; setiap simbol memiliki handle sendiri. |
| `ATRShift` | `1` | ATR dari candle yang sudah closed. |
| `ATRMultiplier` | `1.0` | Jarak SL = satu ATR. |
| `TrailingAnchor` | `ANCHOR_CURRENT_PRICE` | BUY dari Bid saat ini; SELL dari Ask saat ini. |
| `Activation` | `ACTIVATION_OFF` | Trailing langsung aktif. |
| `UseMinimumTrailingStep` | `false` | Tidak ada gate langkah minimum. |
| filter posisi | sesuai PRD | Hanya simbol chart, BUY dan SELL, manual diizinkan. |

Rumus baseline:

```text
BUY  CandidateSL = Bid - ATR[ATRShift] × ATRMultiplier
SELL CandidateSL = Ask + ATR[ATRShift] × ATRMultiplier
```

SL bergerak satu arah saja: SL BUY baru harus lebih tinggi; SL SELL baru harus lebih rendah. Jika SL masih `0`, manager dapat memasang SL pertama yang valid.

### Preset eksperimen konsep sebelumnya

Preset berikut **bukan default dan bukan klaim lebih baik**:

```text
TrailingAnchor           = ANCHOR_FAVORABLE_EXTREME
ATRMultiplier            = 2.5
Activation               = ACTIVATION_ATR
ActivationATR            = 1.0
UseMinimumTrailingStep   = true
MinimumStepATR           = 0.10
```

Dalam mode eksperimental, BUY menggunakan `HighestBidSinceOpen` dan SELL menggunakan `LowestAskSinceOpen`. Nilai ekstrem dipersistenkan dengan MT5 Terminal Global Variables dan dipulihkan atau direkonstruksi secara konservatif sesudah restart. Baseline tidak membutuhkan ekstrem historis untuk menghitung kandidat SL berikutnya.

## Filter dan aktivasi

Posisi dikelola hanya jika seluruh filter aktif lolos:

- `ManageCurrentSymbolOnly` membatasi pada simbol chart.
- `ApplyToDirection` mendukung BUY+SELL, BUY saja, atau SELL saja.
- `ManageManualTrades=false` mengecualikan posisi magic `0`.
- `UseMagicNumberFilter=true` membutuhkan `MagicNumber` yang sama.
- `UseCommentFilter=true` menerapkan pencocokan substring case-sensitive pada `CommentFilter`; string filter kosong ditolak saat inisialisasi.

Mode aktivasi:

- `ACTIVATION_OFF`: trailing langsung aktif.
- `ACTIVATION_ATR`: BUY aktif pada `Open + ATR[shift] × ActivationATR`; SELL pada `Open - ATR[shift] × ActivationATR`. ATR dihitung ulang sebelum aktif, tidak dibekukan saat discovery.
- `ACTIVATION_POINTS`: menggunakan `ActivationPoints × SYMBOL_POINT`.

Setelah aktif, trailing tetap latched hingga posisi tidak lagi dikelola.

## Broker safeguards

Sebelum mengirim `TRADE_ACTION_SLTP` dengan `request.position = ticket`, manager:

1. Mengambil Bid/Ask baru per simbol dan ATR valid pada `ATRShift` yang dipilih.
2. Menormalisasi kandidat terhadap `SYMBOL_TRADE_TICK_SIZE` dan `SYMBOL_DIGITS`.
3. Menyesuaikan kandidat terhadap `SYMBOL_TRADE_STOPS_LEVEL`, lalu memeriksa ulang bahwa SL masih lebih protektif.
4. Melewati permintaan dalam `SYMBOL_TRADE_FREEZE_LEVEL`.
5. Membaca ulang SL dan TP posisi yang sama tepat sebelum request.
6. Mengirim TP yang sudah ada tanpa membuat, menghapus, memperlebar, atau mempersempit TP.
7. Memeriksa hasil lokal `OrderSend()` serta retcode server.

Tidak ada logika pip tetap, nama simbol hardcoded, atau modifikasi berbasis simbol saja; ini memungkinkan validasi EURUSD, GBPUSD, USDJPY, dan NAS100/US100/USTEC versi broker.

## Uji demo manual

1. Gunakan akun demo dan buka BUY atau SELL pada simbol chart.
2. Attach `ATR_Trailing_Manager_v1_Beta_R1` menggunakan baseline default.
3. Pantau tab **Experts** untuk `POSITION_DISCOVERED`, `TRAILING_ACTIVATED`, validasi broker, dan `SL_MODIFY_SUCCESS`.
4. Pastikan di tab Trade bahwa TP tidak berubah dan setiap SL berikutnya lebih protektif.
5. Ulangi dengan SL awal, tanpa SL awal, BUY, SELL, dan filter yang berbeda.

## Strategy Tester dan harness

Manager sengaja tidak memiliki entry logic. Gunakan `ATR_Trailing_TestHarness` untuk membuat posisi uji yang terpisah dari manager:

1. Compile manager R1 dan harness.
2. Jalankan harness dengan `TestMagicNumber`, arah, volume, serta pilihan SL/TP awal yang diketahui. Harness membuka **satu** posisi pada tick pertama dan tidak melakukan retry otomatis.
3. Jalankan manager dengan `UseMagicNumberFilter=true` dan `MagicNumber` sama dengan harness untuk mengisolasi posisi tes.
4. Gunakan workflow/test environment yang mampu memasang kedua EA pada akun simulasi yang sama, atau gunakan harness untuk memvalidasi entry dan lakukan pengujian manager pada posisi demo manual yang ekuivalen.
5. Untuk perbandingan A/B, gunakan entry, data tick, simbol, timeframe, dan periode yang identik. Ubah satu faktor riset pada satu waktu.

Strategy Tester visual standar dapat membatasi satu EA pada satu chart. Keterbatasan ini tidak boleh diatasi dengan menambah logic entry ke manager.

## Log keputusan

Semua catatan manager memakai prefix `[ATRTS]`. Catatan evaluasi membawa ticket `ulong`, identifier, simbol, sisi posisi, mode anchor/aktivasi, Bid, Ask, spread, ATR, `ATRShift`, harga anchor, kandidat mentah/ternormalisasi, tick size, point, stop/freeze level, dan retcode.

Kode utama:

| Kode | Arti |
|---|---|
| `POSITION_DISCOVERED`, `STATE_INITIALIZED`, `STATE_RESTORED` | Siklus hidup state posisi. |
| `STATE_DEGRADED_REINIT` | Riwayat tick tidak cukup untuk merekonstruksi ekstrem eksperimen; inisialisasi konservatif digunakan. |
| `TRAILING_NOT_ACTIVATED`, `TRAILING_ACTIVATED` | Hasil gate aktivasi. |
| `NO_BETTER_SL`, `SKIP_MIN_STEP`, `SKIP_MODIFICATION_INTERVAL`, `SKIP_STOP_LEVEL`, `SKIP_FREEZE_LEVEL` | Kandidat tidak boleh atau tidak dapat dikirim. |
| `STATE_RESTORED_CANDIDATE_INVALID` | Ekstrem hasil pemulihan tidak valid terhadap pasar saat ini; kandidat tetap melalui validasi broker dan tidak pernah melonggarkan SL. |
| `SKIP_INVALID_ATR`, `SKIP_INVALID_TICK`, `SKIP_INVALID_PRICE`, `SKIP_POSITION_GONE` | Data runtime tidak valid atau posisi hilang. |
| `AUTOTRADING_DISABLED_TERMINAL`, `AUTOTRADING_DISABLED_PROGRAM`, `ACCOUNT_TRADE_NOT_ALLOWED`, `SYMBOL_TRADE_DISABLED` | Diagnostik izin trading yang spesifik. |
| `SL_MODIFY_SENT`, `SL_MODIFY_SUCCESS`, `SL_MODIFY_REJECTED` | Siklus request per-ticket dan respons server. |
| `POSITION_CLOSED`, `STATE_CLEANUP` | Pembersihan state memory/persisten. |

## Batasan yang diketahui

- Compile F7 dan Strategy Tester belum dapat divalidasi dari Linux karena MetaEditor/MQL5 compiler tidak tersedia di environment ini. Catat bukti uji Windows/MT5 pada `TEST_MATRIX.md`.
- Server broker tetap otoritatif saat request tiba; stop/freeze level dapat berubah setelah pemeriksaan lokal.
- Mode favorable-extreme hanya seakurat Global Variables atau tick history yang tersedia. Jika riwayat tidak tersedia, manager tidak mengarang ekstrem lama dan tidak pernah melonggarkan SL.
- Hasil riset trailing bukan bukti profitabilitas. Jangan optimasi banyak faktor eksperimental secara bersamaan sebelum baseline stabil.
