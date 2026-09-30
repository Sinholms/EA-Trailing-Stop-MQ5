# Test Matrix — ATR Trailing Stop Manager EA v1 Beta R1

> Isi kolom **Actual Result** dan **Pass/Fail** hanya setelah test benar-benar dijalankan. Status saat ini: belum tervalidasi di MetaEditor/Strategy Tester karena toolchain MQL5 tidak tersedia pada Linux.

## Metadata pelaksanaan

| Field | Value |
|---|---|
| Build MT5/MetaEditor | `TBD` |
| Broker/account | `TBD` (target: HFM Demo MT5) |
| Account mode | `TBD` (netting/hedging) |
| Symbol | `TBD` |
| Timeframe | `TBD` |
| Modelling mode / tick source | `TBD` |
| EA version | `v1 Beta R1` |
| Tester date range | `TBD` |

## Baseline control

Gunakan baseline ini kecuali baris menyatakan sebaliknya:

```text
ATRPeriod=14; ATRTimeframe=PERIOD_CURRENT; ATRShift=1; ATRMultiplier=1.0
TrailingAnchor=ANCHOR_CURRENT_PRICE; Activation=ACTIVATION_OFF
UseMinimumTrailingStep=false; ManageCurrentSymbolOnly=true
ApplyToDirection=APPLY_BUY_AND_SELL; ManageManualTrades=true
UseMagicNumberFilter=false; UseCommentFilter=false; EnableDebugLog=true
```

## Required test cases

| ID | Skenario | Expected Result | Actual Result | Pass/Fail |
|---|---|---|---|---|
| 01 | BUY tanpa SL awal | SL valid pertama dapat dipasang dan selanjutnya tidak mundur. | `TBD` | `TBD` |
| 02 | SELL tanpa SL awal | SL valid pertama dapat dipasang dan selanjutnya tidak mundur. | `TBD` | `TBD` |
| 03 | BUY dengan SL awal | Kandidat lebih buruk tidak mengubah SL. | `TBD` | `TBD` |
| 04 | SELL dengan SL awal | Kandidat lebih buruk tidak mengubah SL. | `TBD` | `TBD` |
| 05 | Current-price anchor BUY | Candidate = Bid − ATR[1] × multiplier. | `TBD` | `TBD` |
| 06 | Current-price anchor SELL | Candidate = Ask + ATR[1] × multiplier. | `TBD` | `TBD` |
| 07 | Favorable-extreme anchor BUY | Candidate memakai high Bid sejak open. | `TBD` | `TBD` |
| 08 | Favorable-extreme anchor SELL | Candidate memakai low Ask sejak open. | `TBD` | `TBD` |
| 09 | Immediate activation | `ACTIVATION_OFF` aktif segera saat posisi eligible. | `TBD` | `TBD` |
| 10 | ATR activation sebelum threshold | Tidak ada SL modification sebelum ambang terpenuhi. | `TBD` | `TBD` |
| 11 | ATR activation crossing threshold | Trailing aktif saat ambang ATR dilintasi. | `TBD` | `TBD` |
| 12 | Points activation crossing threshold | Trailing aktif terhadap `ActivationPoints × SYMBOL_POINT`. | `TBD` | `TBD` |
| 13 | Activation latch | Trailing tetap aktif walau harga kembali melewati ambang. | `TBD` | `TBD` |
| 14 | ATR shift 1 | Log dan kandidat memakai ATR candle closed, bukan buffer 0. | `TBD` | `TBD` |
| 15 | ATR unavailable / CopyBuffer failure | `SKIP_INVALID_ATR`; tidak ada request SL. | `TBD` | `TBD` |
| 16 | Minimum step disabled | Perbaikan SL valid tidak diblokir gate minimum step. | `TBD` | `TBD` |
| 17 | Minimum step enabled | Improvement di bawah jarak ATR menghasilkan `SKIP_MIN_STEP`. | `TBD` | `TBD` |
| 18 | Stop level | Kandidat disesuaikan ke broker-valid atau dilewati aman. | `TBD` | `TBD` |
| 19 | Freeze level | `SKIP_FREEZE_LEVEL`; tidak ada spam request pada kondisi sama. | `TBD` | `TBD` |
| 20 | Tick-size normalization | Harga SL berada pada grid `SYMBOL_TRADE_TICK_SIZE`. | `TBD` | `TBD` |
| 21 | CFD/index tick size | Valid pada tick size non-Forex. | `TBD` | `TBD` |
| 22 | Valid SL modification | `SL_MODIFY_SUCCESS` dan SL server sesuai kandidat valid. | `TBD` | `TBD` |
| 23 | Local modify failure | `SL_MODIFY_REJECTED` mencatat local error tanpa immediate retry. | `TBD` | `TBD` |
| 24 | Server retcode rejection | Retcode non-sukses dicatat sebagai rejection walau request lokal terkirim. | `TBD` | `TBD` |
| 25 | Multiple hedged positions | Beberapa posisi pada simbol sama diproses secara independen. | `TBD` | `TBD` |
| 26 | Exact ticket target | SL berubah hanya pada ticket yang dituju. | `TBD` | `TBD` |
| 27 | Netting behavior | Posisi netting dikelola aman setelah perubahan volume/direction. | `TBD` | `TBD` |
| 28 | Large ticket | Ticket di atas signed 32-bit tetap dibaca dan ditarget tepat. | `TBD` | `TBD` |
| 29 | Manual trade | Posisi magic `0` dikelola ketika `ManageManualTrades=true`. | `TBD` | `TBD` |
| 30 | Magic included | Posisi magic yang sama dikelola saat filter aktif. | `TBD` | `TBD` |
| 31 | Magic excluded | Posisi magic berbeda tidak dikelola saat filter aktif. | `TBD` | `TBD` |
| 32 | Comment included | Comment yang mengandung `CommentFilter` dikelola. | `TBD` | `TBD` |
| 33 | Comment excluded | Comment yang tidak mengandung filter tidak dikelola. | `TBD` | `TBD` |
| 34 | BUY-only filter | Hanya BUY yang dikelola. | `TBD` | `TBD` |
| 35 | SELL-only filter | Hanya SELL yang dikelola. | `TBD` | `TBD` |
| 36 | Multi-symbol management | Saat current-symbol-only OFF, ATR berasal dari simbol posisi dengan timeframe konfigurasi. | `TBD` | `TBD` |
| 37 | Symbol suffix | Simbol broker bersufiks tetap diproses tanpa hardcoding. | `TBD` | `TBD` |
| 38 | Chart timeframe behavior | `PERIOD_CURRENT` konsisten memakai timeframe chart untuk setiap simbol. | `TBD` | `TBD` |
| 39 | Restart current-price mode | SL tidak longgar dan TP tetap tanpa extrema persistence. | `TBD` | `TBD` |
| 40 | Restart favorable-extreme valid state | State valid dipulihkan dan stop path tetap dapat diaudit. | `TBD` | `TBD` |
| 41 | Restart favorable-extreme missing state | `STATE_DEGRADED_REINIT`; re-init konservatif. | `TBD` | `TBD` |
| 42 | Restored candidate invalid | `STATE_RESTORED_CANDIDATE_INVALID`; tidak ada SL di sisi pasar salah. | `TBD` | `TBD` |
| 43 | Position closed while running | Memory dan Global Variables stale dibersihkan. | `TBD` | `TBD` |
| 44 | External SL/TP modification | Tick berikutnya membaca server state; manager tidak mengubah TP. | `TBD` | `TBD` |
| 45 | TP preservation after updates | TP identik setelah beberapa update SL. | `TBD` | `TBD` |
| 46 | Terminal/program autotrading disabled | Kode diagnostik paling spesifik muncul. | `TBD` | `TBD` |
| 47 | Symbol trading disabled | `SYMBOL_TRADE_DISABLED` muncul dan tidak ada request. | `TBD` | `TBD` |
| 48 | Market closed / invalid tick | `SKIP_INVALID_TICK`; EA tidak crash atau retry agresif. | `TBD` | `TBD` |
| 49 | Orphan state cleanup | Terminal Global Variables tanpa posisi aktif dibersihkan. | `TBD` | `TBD` |
| 50 | No immediate retry flooding | Satu rejection menunggu tick masa depan dan evaluasi data baru. | `TBD` | `TBD` |

## Tambahan release gate

| ID | Skenario | Expected Result | Actual Result | Pass/Fail |
|---|---|---|---|---|
| G1 | Compile manager R1 F7 | Bersih dari error; setiap warning ditinjau dan dicatat. | `TBD` | `TBD` |
| G2 | Compile harness F7 | Bersih dari error; harness terpisah dan tester-only. | `TBD` | `TBD` |
| G3 | HFM Demo smoke test | Baseline berjalan tanpa source change pada simbol broker yang valid. | `TBD` | `TBD` |
| G4 | Controlled A/B | Entry, tick data, simbol, timeframe, dan periode identik; satu faktor utama berubah. | `TBD` | `TBD` |

## Bukti yang dilampirkan per run

- Screenshot hasil compile F7 kedua `.mq5`.
- Journal/Experts log untuk kandidat, keputusan broker, dan retcode.
- Screenshot Trade tab sebelum/sesudah untuk SL, TP, dan ticket target.
- Input set (`.set`) atau daftar parameter lengkap.
- Informasi broker, account mode, simbol, timeframe, rentang tanggal, dan mode modeling.
- Untuk A/B: kedua run harus memakai entry dan data tick yang sama; ubah satu faktor utama per perbandingan.
