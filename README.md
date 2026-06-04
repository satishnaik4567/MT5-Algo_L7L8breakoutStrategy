# 📈 MT5 NYKX Morning Volatility Breakout (L7/L8)

An automated MetaTrader 5 Expert Advisor (EA) written in MQL5. This strategy was systematically ported from TradingView Pine Script to MetaTrader 5 to leverage MT5's superior execution speed and Order Cancels Order (OCO) mechanics.

## 🧠 Algorithmic Logic & Market Structure

The NYKX strategy is designed to capitalize on morning session volatility by calculating micro-percentage thresholds derived from the first 5-minute candle of the trading day.

### 1. Session Initialization
The algorithm isolates the high ($H$) and low ($L$) of the very first closed 5-minute candle of the day. From this, it establishes the session midpoint ($M$):
$M = \frac{H + L}{2}$

### 2. Quantitative Thresholds
The EA generates 8 price levels using specific percentage deviations (`0.2618%` and `0.1309%`). The primary execution triggers (L7 and L8) are calculated as follows:
*   **Long Entry Trigger (L7):** $L_7 = M \times (1 + 0.001309)$
*   **Short Entry Trigger (L8):** $L_8 = M \times (1 - 0.001309)$

### 3. Execution Mechanics
*   **Crossover Detection:** The EA monitors the most recently closed bar. A **LONG** order is fired when the previous bar closes $\le L_7$ and the current bar closes $> L_7$.
*   **Risk Management:** Fixed pipeline execution. Stop Loss is hardcoded at 70 pips, and Take Profit at 300 pips.
*   **Trade Frequency:** Hardcapped at exactly one execution per day to prevent over-trading in ranging markets.
*   **State Reset:** Automatically purges chart objects, session variables, and crossover states at `00:00:00` daily.

## ⚙️ Installation & Usage

1. Download the `NYKX_Morning_Breakout.mq5` file.
2. Place it in your MT5 Experts folder: `File -> Open Data Folder -> MQL5 -> Experts`.
3. Open MetaEditor and compile the `.mq5` file.
4. Attach the EA to an `M5` chart.

### Configurable Input Parameters
| Variable | Default | Description |
| :--- | :--- | :--- |
| `InpLotSize` | `0.1` | Fixed position sizing |
| `InpSLPips` | `70.0` | Stop Loss distance in pips |
| `InpTPPips` | `300.0` | Take Profit distance in pips |
| `InpMagicNumber`| `202504` | Unique EA identifier |

## 💻 Technical Highlights
* **Memory Management:** Efficient use of `ObjectsDeleteAll()` to ensure MT5 terminals do not bloat with historical chart objects over time.
* **Tick Optimization:** Utilizes `lastBarTime` tracking within `OnTick()` to ensure complex calculations only run once per closed bar, heavily reducing CPU overhead during backtesting and live execution.
