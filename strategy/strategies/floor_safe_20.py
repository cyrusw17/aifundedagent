"""Twenty prop-floor-safe causal strategies (The5ers $6k floor).

Fills only after knowable_at. PROP: never hit $94k; max_dd <= $6k.
Generated from results/floor_safe_20.json — do not hand-edit params lightly.
"""
from __future__ import annotations

from dataclasses import replace
from typing import Callable, Dict, Optional

from ..config import PARAMS, StrategyParams
from .h1_models import H1Cfg, make_fn as make_h1
from .kb_models import Cfg, make_fn as make_ict
from .retail_models import RetailCfg, make_fn as make_retail
from .retail_models_v2 import RetailCfg2, make_fn2
from .swing_retail import SwingCfg, make_swing_fn

HALTS: Dict[str, float] = {}
HOLDS: Dict[str, int] = {}
RISKS: Dict[str, float] = {}
STRATEGIES: Dict[str, Callable] = {}
STRATEGY_DESC: Dict[str, str] = {}
META: Dict[str, dict] = {}

def _register():
    global HALTS, HOLDS, RISKS, STRATEGIES, STRATEGY_DESC, META
    # --- A1_H1Don_n35_rr5 (h1_don) ann=2.99% dd=$5050 ---
    cfg = H1Cfg(
        tag='A1_H1Don_n35_rr5', model='don_h1', rr=5.0,
        don_len=35,
        max_hold_days=3, stop_atr=2.0, session_only=True, risk_pct=0.0035,
        flatten_hour_utc=22, move_to_be=False,
    )
    STRATEGIES['A1_H1Don_n35_rr5'] = make_h1(cfg)
    HALTS['A1_H1Don_n35_rr5'] = 5000.0
    HOLDS['A1_H1Don_n35_rr5'] = 3
    RISKS['A1_H1Don_n35_rr5'] = 0.0035
    STRATEGY_DESC['A1_H1Don_n35_rr5'] = 'h1_don don_h1, floor-safe risk 0.35%, halt $5,000, ann~3.0%, dd~$5050'
    META['A1_H1Don_n35_rr5'] = {'family': 'h1_don', 'ann': 2.99, 'max_dd': 5049.71, 'pf': 1.408}

    # --- A2_H1Don_n30_rr4 (h1_don) ann=2.06% dd=$4962 ---
    cfg = H1Cfg(
        tag='A2_H1Don_n30_rr4', model='don_h1', rr=4.0,
        don_len=30,
        max_hold_days=1, stop_atr=2.0, session_only=True, risk_pct=0.005,
        flatten_hour_utc=22, move_to_be=False,
    )
    STRATEGIES['A2_H1Don_n30_rr4'] = make_h1(cfg)
    HALTS['A2_H1Don_n30_rr4'] = 4500.0
    HOLDS['A2_H1Don_n30_rr4'] = 1
    RISKS['A2_H1Don_n30_rr4'] = 0.005
    STRATEGY_DESC['A2_H1Don_n30_rr4'] = 'h1_don don_h1, floor-safe risk 0.50%, halt $4,500, ann~2.1%, dd~$4962'
    META['A2_H1Don_n30_rr4'] = {'family': 'h1_don', 'ann': 2.06, 'max_dd': 4962.17, 'pf': 1.566}

    # --- A3_H1Don_n40_rr4 (h1_don) ann=2.87% dd=$4681 ---
    cfg = H1Cfg(
        tag='A3_H1Don_n40_rr4', model='don_h1', rr=4.0,
        don_len=40,
        max_hold_days=1, stop_atr=2.0, session_only=True, risk_pct=0.005,
        flatten_hour_utc=22, move_to_be=False,
    )
    STRATEGIES['A3_H1Don_n40_rr4'] = make_h1(cfg)
    HALTS['A3_H1Don_n40_rr4'] = 4500.0
    HOLDS['A3_H1Don_n40_rr4'] = 1
    RISKS['A3_H1Don_n40_rr4'] = 0.005
    STRATEGY_DESC['A3_H1Don_n40_rr4'] = 'h1_don don_h1, floor-safe risk 0.50%, halt $4,500, ann~2.9%, dd~$4681'
    META['A3_H1Don_n40_rr4'] = {'family': 'h1_don', 'ann': 2.87, 'max_dd': 4681.11, 'pf': 1.825}

    # --- A4_ICT_MSB_PA (ict_sb) ann=1.43% dd=$4708 ---
    cfg = Cfg(tag='A4_ICT_MSB_PA', model='sb_fvg', risk_pct=0.005, rr=3.5, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=True, strict_bias=False, sb_start=14.0, sb_end=15.0, orb_end='07:45', sb_windows=[[14.0, 15.0]], flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['A4_ICT_MSB_PA'] = make_ict(cfg)
    HALTS['A4_ICT_MSB_PA'] = 4500.0
    HOLDS['A4_ICT_MSB_PA'] = 0
    RISKS['A4_ICT_MSB_PA'] = 0.005
    STRATEGY_DESC['A4_ICT_MSB_PA'] = 'ict_sb sb_fvg, floor-safe risk 0.50%, halt $4,500, ann~1.4%, dd~$4708'
    META['A4_ICT_MSB_PA'] = {'family': 'ict_sb', 'ann': 1.43, 'max_dd': 4708.48, 'pf': 1.329}

    # --- A5_ICT_MSB_ASIA (ict_sb) ann=1.84% dd=$4184 ---
    cfg = Cfg(tag='A5_ICT_MSB_ASIA', model='sb_fvg', risk_pct=0.005, rr=3.5, min_body_atr=0.45, min_fvg_atr=0.12, use_pdh=False, use_asia=True, strict_bias=False, sb_start=14.0, sb_end=15.0, orb_end='07:45', sb_windows=[[14.0, 15.0]], flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['A5_ICT_MSB_ASIA'] = make_ict(cfg)
    HALTS['A5_ICT_MSB_ASIA'] = 4000.0
    HOLDS['A5_ICT_MSB_ASIA'] = 0
    RISKS['A5_ICT_MSB_ASIA'] = 0.005
    STRATEGY_DESC['A5_ICT_MSB_ASIA'] = 'ict_sb sb_fvg, floor-safe risk 0.50%, halt $4,000, ann~1.8%, dd~$4184'
    META['A5_ICT_MSB_ASIA'] = {'family': 'ict_sb', 'ann': 1.84, 'max_dd': 4183.9, 'pf': 1.542}

    # --- H1EMA_12_48_rr4_h3 (h1_ema) ann=2.97% dd=$4847 ---
    cfg = H1Cfg(
        tag='H1EMA_12_48_rr4_h3', model='ema_h1', rr=4.0,
        ema_fast=12, ema_slow=48,
        max_hold_days=3, stop_atr=2.0, session_only=True, risk_pct=0.005,
        flatten_hour_utc=22, move_to_be=False,
    )
    STRATEGIES['H1EMA_12_48_rr4_h3'] = make_h1(cfg)
    HALTS['H1EMA_12_48_rr4_h3'] = 4500.0
    HOLDS['H1EMA_12_48_rr4_h3'] = 3
    RISKS['H1EMA_12_48_rr4_h3'] = 0.005
    STRATEGY_DESC['H1EMA_12_48_rr4_h3'] = 'h1_ema ema_h1, floor-safe risk 0.50%, halt $4,500, ann~3.0%, dd~$4847'
    META['H1EMA_12_48_rr4_h3'] = {'family': 'h1_ema', 'ann': 2.97, 'max_dd': 4846.72, 'pf': 1.316}

    # --- H1Don_n55_rr4_h3 (h1_don) ann=2.03% dd=$4893 ---
    cfg = H1Cfg(
        tag='H1Don_n55_rr4_h3', model='don_h1', rr=4.0,
        don_len=55,
        max_hold_days=3, stop_atr=2.0, session_only=True, risk_pct=0.005,
        flatten_hour_utc=22, move_to_be=False,
    )
    STRATEGIES['H1Don_n55_rr4_h3'] = make_h1(cfg)
    HALTS['H1Don_n55_rr4_h3'] = 4500.0
    HOLDS['H1Don_n55_rr4_h3'] = 3
    RISKS['H1Don_n55_rr4_h3'] = 0.005
    STRATEGY_DESC['H1Don_n55_rr4_h3'] = 'h1_don don_h1, floor-safe risk 0.50%, halt $4,500, ann~2.0%, dd~$4893'
    META['H1Don_n55_rr4_h3'] = {'family': 'h1_don', 'ann': 2.03, 'max_dd': 4892.82, 'pf': 1.695}

    # --- R2_EMA_ADX_rr25 (retail) ann=1.12% dd=$4597 ---
    cfg = RetailCfg2(tag='R2_EMA_ADX_rr25', model='ema_rsi_adx', risk_pct=0.005, rr=2.5, stop_atr=1.2, ema_trend=50, rsi_lo=35, rsi_hi=65, adx_min=20, killzone_only=True, use_h1_bias=True, flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['R2_EMA_ADX_rr25'] = make_fn2(cfg)
    HALTS['R2_EMA_ADX_rr25'] = 4500.0
    HOLDS['R2_EMA_ADX_rr25'] = 0
    RISKS['R2_EMA_ADX_rr25'] = 0.005
    STRATEGY_DESC['R2_EMA_ADX_rr25'] = 'retail ema_rsi_adx, floor-safe risk 0.50%, halt $4,500, ann~1.1%, dd~$4597'
    META['R2_EMA_ADX_rr25'] = {'family': 'retail', 'ann': 1.12, 'max_dd': 4596.63, 'pf': 1.388}

    # --- R2_ROC_rr25 (retail) ann=0.16% dd=$4848 ---
    cfg = RetailCfg2(tag='R2_ROC_rr25', model='roc_break', risk_pct=0.004, rr=2.5, stop_atr=1.2, ema_trend=50, rsi_lo=35.0, rsi_hi=65.0, adx_min=20.0, killzone_only=True, use_h1_bias=True, flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['R2_ROC_rr25'] = make_fn2(cfg)
    HALTS['R2_ROC_rr25'] = 4500.0
    HOLDS['R2_ROC_rr25'] = 0
    RISKS['R2_ROC_rr25'] = 0.004
    STRATEGY_DESC['R2_ROC_rr25'] = 'retail roc_break, floor-safe risk 0.40%, halt $4,500, ann~0.2%, dd~$4848'
    META['R2_ROC_rr25'] = {'family': 'retail', 'ann': 0.16, 'max_dd': 4847.82, 'pf': 1.053}

    # --- R_ema_rsi_rr20_100_30_70_12 (retail) ann=0.52% dd=$4882 ---
    cfg = RetailCfg(tag='R_ema_rsi_rr20_100_30_70_12', model='ema_rsi', risk_pct=0.005, rr=2.0, stop_atr=1.2, ema_fast=9, ema_slow=21, ema_trend=100, rsi_lo=30, rsi_hi=70, don_len=20, bb_std=2.0, st_mult=3.0, vwap_z=1.5, killzone_only=True, flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['R_ema_rsi_rr20_100_30_70_12'] = make_retail(cfg)
    HALTS['R_ema_rsi_rr20_100_30_70_12'] = 4500.0
    HOLDS['R_ema_rsi_rr20_100_30_70_12'] = 0
    RISKS['R_ema_rsi_rr20_100_30_70_12'] = 0.005
    STRATEGY_DESC['R_ema_rsi_rr20_100_30_70_12'] = 'retail ema_rsi, floor-safe risk 0.50%, halt $4,500, ann~0.5%, dd~$4882'
    META['R_ema_rsi_rr20_100_30_70_12'] = {'family': 'retail', 'ann': 0.52, 'max_dd': 4881.81, 'pf': 1.124}

    # --- R_donchian_rr20_20_12 (retail) ann=0.17% dd=$4862 ---
    cfg = RetailCfg(tag='R_donchian_rr20_20_12', model='donchian', risk_pct=0.004, rr=2.0, stop_atr=1.2, ema_fast=9, ema_slow=21, ema_trend=50, rsi_lo=35.0, rsi_hi=65.0, don_len=20, bb_std=2.0, st_mult=3.0, vwap_z=1.5, killzone_only=True, flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['R_donchian_rr20_20_12'] = make_retail(cfg)
    HALTS['R_donchian_rr20_20_12'] = 4500.0
    HOLDS['R_donchian_rr20_20_12'] = 0
    RISKS['R_donchian_rr20_20_12'] = 0.004
    STRATEGY_DESC['R_donchian_rr20_20_12'] = 'retail donchian, floor-safe risk 0.40%, halt $4,500, ann~0.2%, dd~$4862'
    META['R_donchian_rr20_20_12'] = {'family': 'retail', 'ann': 0.17, 'max_dd': 4862.03, 'pf': 1.066}

    # --- DonD_n40_rr3_h10 (swing) ann=0.86% dd=$4104 ---
    cfg = SwingCfg(tag='DonD_n40_rr3_h10', model='don_daily', rr=3.0, max_hold_days=10, flatten_hour_utc=23, don_len=40, ema_fast=20, ema_slow=50, stop_atr_mult=2.0)
    STRATEGIES['DonD_n40_rr3_h10'] = make_swing_fn(cfg)
    HALTS['DonD_n40_rr3_h10'] = 4500.0
    HOLDS['DonD_n40_rr3_h10'] = 10
    RISKS['DonD_n40_rr3_h10'] = 0.005
    STRATEGY_DESC['DonD_n40_rr3_h10'] = 'swing don_daily, floor-safe risk 0.50%, halt $4,500, ann~0.9%, dd~$4104'
    META['DonD_n40_rr3_h10'] = {'family': 'swing', 'ann': 0.86, 'max_dd': 4103.8, 'pf': 1.204}

    # --- DonD_n20_rr4_h8 (swing) ann=0.51% dd=$4038 ---
    cfg = SwingCfg(tag='DonD_n20_rr4_h8', model='don_daily', rr=4.0, max_hold_days=8, flatten_hour_utc=23, don_len=20, ema_fast=20, ema_slow=50, stop_atr_mult=2.0)
    STRATEGIES['DonD_n20_rr4_h8'] = make_swing_fn(cfg)
    HALTS['DonD_n20_rr4_h8'] = 4500.0
    HOLDS['DonD_n20_rr4_h8'] = 8
    RISKS['DonD_n20_rr4_h8'] = 0.004
    STRATEGY_DESC['DonD_n20_rr4_h8'] = 'swing don_daily, floor-safe risk 0.40%, halt $4,500, ann~0.5%, dd~$4038'
    META['DonD_n20_rr4_h8'] = {'family': 'swing', 'ann': 0.51, 'max_dd': 4037.8, 'pf': 1.121}

    # --- EmaD_20_50_rr25_h5 (swing) ann=0.56% dd=$3006 ---
    cfg = SwingCfg(tag='EmaD_20_50_rr25_h5', model='ema_daily', rr=2.5, max_hold_days=5, flatten_hour_utc=23, don_len=20, ema_fast=20, ema_slow=50, stop_atr_mult=2.0)
    STRATEGIES['EmaD_20_50_rr25_h5'] = make_swing_fn(cfg)
    HALTS['EmaD_20_50_rr25_h5'] = 4500.0
    HOLDS['EmaD_20_50_rr25_h5'] = 5
    RISKS['EmaD_20_50_rr25_h5'] = 0.005
    STRATEGY_DESC['EmaD_20_50_rr25_h5'] = 'swing ema_daily, floor-safe risk 0.50%, halt $4,500, ann~0.6%, dd~$3006'
    META['EmaD_20_50_rr25_h5'] = {'family': 'swing', 'ann': 0.56, 'max_dd': 3005.92, 'pf': 1.175}

    # --- FS_W4_SB14_ASIA_r6 (ict_sb) ann=0.98% dd=$4621 ---
    cfg = Cfg(tag='FS_W4_SB14_ASIA_r6', model='sb_fvg', risk_pct=0.005, rr=3.0, min_body_atr=0.35, min_fvg_atr=0.1, use_pdh=False, use_asia=True, strict_bias=False, sb_start=14.0, sb_end=15.0, orb_end='07:45', sb_windows=[[7.0, 8.0], [14.0, 15.0], [15.0, 16.0]], flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['FS_W4_SB14_ASIA_r6'] = make_ict(cfg)
    HALTS['FS_W4_SB14_ASIA_r6'] = 4500.0
    HOLDS['FS_W4_SB14_ASIA_r6'] = 0
    RISKS['FS_W4_SB14_ASIA_r6'] = 0.005
    STRATEGY_DESC['FS_W4_SB14_ASIA_r6'] = 'ict_sb sb_fvg, floor-safe risk 0.50%, halt $4,500, ann~1.0%, dd~$4621'
    META['FS_W4_SB14_ASIA_r6'] = {'family': 'ict_sb', 'ann': 0.98, 'max_dd': 4620.85, 'pf': 1.247}

    # --- H1Don_n35_rr4_h1 (h1_don) ann=2.77% dd=$4910 ---
    cfg = H1Cfg(
        tag='H1Don_n35_rr4_h1', model='don_h1', rr=4.0,
        don_len=35,
        max_hold_days=1, stop_atr=2.0, session_only=True, risk_pct=0.005,
        flatten_hour_utc=22, move_to_be=False,
    )
    STRATEGIES['H1Don_n35_rr4_h1'] = make_h1(cfg)
    HALTS['H1Don_n35_rr4_h1'] = 4500.0
    HOLDS['H1Don_n35_rr4_h1'] = 1
    RISKS['H1Don_n35_rr4_h1'] = 0.005
    STRATEGY_DESC['H1Don_n35_rr4_h1'] = 'h1_don don_h1, floor-safe risk 0.50%, halt $4,500, ann~2.8%, dd~$4910'
    META['H1Don_n35_rr4_h1'] = {'family': 'h1_don', 'ann': 2.77, 'max_dd': 4909.67, 'pf': 1.789}

    # --- H1EMA_15_45_rr4_h3 (h1_ema) ann=0.88% dd=$4675 ---
    cfg = H1Cfg(
        tag='H1EMA_15_45_rr4_h3', model='ema_h1', rr=4.0,
        ema_fast=15, ema_slow=45,
        max_hold_days=3, stop_atr=2.0, session_only=True, risk_pct=0.005,
        flatten_hour_utc=22, move_to_be=False,
    )
    STRATEGIES['H1EMA_15_45_rr4_h3'] = make_h1(cfg)
    HALTS['H1EMA_15_45_rr4_h3'] = 4500.0
    HOLDS['H1EMA_15_45_rr4_h3'] = 3
    RISKS['H1EMA_15_45_rr4_h3'] = 0.005
    STRATEGY_DESC['H1EMA_15_45_rr4_h3'] = 'h1_ema ema_h1, floor-safe risk 0.50%, halt $4,500, ann~0.9%, dd~$4675'
    META['H1EMA_15_45_rr4_h3'] = {'family': 'h1_ema', 'ann': 0.88, 'max_dd': 4675.14, 'pf': 1.145}

    # --- SB14_PDH_rr30_b35 (ict_sb) ann=0.83% dd=$3012 ---
    cfg = Cfg(tag='SB14_PDH_rr30_b35', model='sb_fvg', risk_pct=0.005, rr=3.0, min_body_atr=0.35, min_fvg_atr=0.15, use_pdh=True, use_asia=False, strict_bias=True, sb_start=14.0, sb_end=15.0, orb_end='07:45', sb_windows=[[7.0, 8.0], [14.0, 15.0], [15.0, 16.0]], flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['SB14_PDH_rr30_b35'] = make_ict(cfg)
    HALTS['SB14_PDH_rr30_b35'] = 4500.0
    HOLDS['SB14_PDH_rr30_b35'] = 0
    RISKS['SB14_PDH_rr30_b35'] = 0.005
    STRATEGY_DESC['SB14_PDH_rr30_b35'] = 'ict_sb sb_fvg, floor-safe risk 0.50%, halt $4,500, ann~0.8%, dd~$3012'
    META['SB14_PDH_rr30_b35'] = {'family': 'ict_sb', 'ann': 0.83, 'max_dd': 3011.56, 'pf': 1.289}

    # --- SB14_PDH_rr25_b40 (ict_sb) ann=0.5% dd=$2514 ---
    cfg = Cfg(tag='SB14_PDH_rr25_b40', model='sb_fvg', risk_pct=0.005, rr=2.5, min_body_atr=0.4, min_fvg_atr=0.15, use_pdh=True, use_asia=False, strict_bias=True, sb_start=14.0, sb_end=15.0, orb_end='07:45', sb_windows=[[7.0, 8.0], [14.0, 15.0], [15.0, 16.0]], flatten_hour_utc=22, move_to_be=False)
    STRATEGIES['SB14_PDH_rr25_b40'] = make_ict(cfg)
    HALTS['SB14_PDH_rr25_b40'] = 4500.0
    HOLDS['SB14_PDH_rr25_b40'] = 0
    RISKS['SB14_PDH_rr25_b40'] = 0.005
    STRATEGY_DESC['SB14_PDH_rr25_b40'] = 'ict_sb sb_fvg, floor-safe risk 0.50%, halt $4,500, ann~0.5%, dd~$2514'
    META['SB14_PDH_rr25_b40'] = {'family': 'ict_sb', 'ann': 0.5, 'max_dd': 2513.75, 'pf': 1.198}

    # --- DonD_n55_rr3_h10 (swing) ann=0.21% dd=$4154 ---
    cfg = SwingCfg(tag='DonD_n55_rr3_h10', model='don_daily', rr=3.0, max_hold_days=10, flatten_hour_utc=23, don_len=55, ema_fast=20, ema_slow=50, stop_atr_mult=2.0)
    STRATEGIES['DonD_n55_rr3_h10'] = make_swing_fn(cfg)
    HALTS['DonD_n55_rr3_h10'] = 4500.0
    HOLDS['DonD_n55_rr3_h10'] = 10
    RISKS['DonD_n55_rr3_h10'] = 0.004
    STRATEGY_DESC['DonD_n55_rr3_h10'] = 'swing don_daily, floor-safe risk 0.40%, halt $4,500, ann~0.2%, dd~$4154'
    META['DonD_n55_rr3_h10'] = {'family': 'swing', 'ann': 0.21, 'max_dd': 4153.94, 'pf': 1.059}

_register()

def prop_params_for(name: str) -> StrategyParams:
    return replace(
        PARAMS,
        risk_pct=RISKS[name],
        max_hold_days=HOLDS[name],
        dd_halt=HALTS[name],
        flatten_hour_utc=22,
        move_to_be=False,
        daily_profit_cap=2_500.0,
        max_trades_per_day=3,
        max_trades_per_pair_day=1,
        max_open_positions=1,
        cooldown_bars_after_trade=1,
    )

