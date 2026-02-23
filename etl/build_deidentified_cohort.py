#!/usr/bin/env python3
"""
Build a de-identified case-level cohort CSV for the Anesthesia Emergence Predictor.

Outputs columns expected by MATLAB pipeline:
- PatientID
- Age
- Sex
- WeightKg
- BMI
- HeightCm
- LBM
- SurgeryDurationMin
- InfusionRateMgPerMin
- ObservedWakeDelayMin (optional)

Source modes:
1) vitaldb-api: generic REST API ingestion (user-configured endpoint + field map)
2) mimiciv-sql: PostgreSQL/MIMIC-style SQL ingestion
3) csv: convert an existing extract CSV to standardized, de-identified format
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, Optional

import numpy as np
import pandas as pd
import requests
from dateutil import parser as dt_parser


DEFAULT_FIELD_MAP = {
    "case_id": ["case_id", "caseid", "subject_id", "stay_id", "hadm_id", "patient_id"],
    "age": ["age", "anchor_age"],
    "sex": ["sex", "gender"],
    "weight_kg": ["weight_kg", "weightkg", "weight", "admission_weight_kg"],
    "height_cm": ["height_cm", "heightcm", "height"],
    "bmi": ["bmi"],
    "surgery_duration_min": ["surgery_duration_min", "case_duration_min", "anesthesia_duration_min", "duration_min"],
    "surgery_start_time": ["surgery_start_time", "anesthesia_start_time", "start_time", "starttime"],
    "surgery_end_time": ["surgery_end_time", "anesthesia_end_time", "end_time", "endtime"],
    "propofol_infusion_mg_per_min": ["propofol_infusion_mg_per_min", "propofol_rate_mg_min", "infusion_rate_mg_per_min"],
    "propofol_total_dose_mg": ["propofol_total_dose_mg", "total_propofol_mg", "propofol_dose_mg"],
    "observed_wake_delay_min": ["observed_wake_delay_min", "wake_delay_min", "ttw_observed_min"],
}


@dataclass
class BuildConfig:
    deid_salt: str
    drop_columns: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build de-identified cohort CSV for AEP")
    parser.add_argument("--source", required=True, choices=["vitaldb-api", "mimiciv-sql", "csv"])
    parser.add_argument("--output", default="data/vitaldb_cases.csv", help="Output CSV path")
    parser.add_argument("--field-map", help="Optional JSON file overriding source field aliases")
    parser.add_argument("--deid-salt", default=os.getenv("AEP_DEID_SALT", "change-me-salt"))

    parser.add_argument("--input-csv", help="Input CSV path when --source=csv")

    parser.add_argument("--api-url", help="REST URL returning case-level JSON list when --source=vitaldb-api")
    parser.add_argument("--api-token", default=os.getenv("VITALDB_API_TOKEN"), help="Bearer token for API")
    parser.add_argument("--api-timeout", type=int, default=60)

    parser.add_argument("--db-uri", default=os.getenv("MIMIC_DB_URI"), help="SQLAlchemy DB URI for MIMIC/Postgres")
    parser.add_argument("--query-file", help="Path to SQL query file")

    return parser.parse_args()


def load_field_map(path: Optional[str]) -> dict[str, list[str]]:
    if not path:
        return DEFAULT_FIELD_MAP
    with open(path, "r", encoding="utf-8") as f:
        custom = json.load(f)
    merged = DEFAULT_FIELD_MAP.copy()
    merged.update(custom)
    return merged


def fetch_api_rows(api_url: str, api_token: Optional[str], timeout: int) -> pd.DataFrame:
    if not api_url:
        raise ValueError("--api-url is required for vitaldb-api source")

    headers = {}
    if api_token:
        headers["Authorization"] = f"Bearer {api_token}"

    response = requests.get(api_url, headers=headers, timeout=timeout)
    response.raise_for_status()

    payload = response.json()
    if isinstance(payload, dict):
        if "results" in payload and isinstance(payload["results"], list):
            rows = payload["results"]
        elif "data" in payload and isinstance(payload["data"], list):
            rows = payload["data"]
        else:
            rows = [payload]
    elif isinstance(payload, list):
        rows = payload
    else:
        raise ValueError("Unsupported API payload format")

    return pd.DataFrame(rows)


def fetch_sql_rows(db_uri: str, query_file: str) -> pd.DataFrame:
    sqlalchemy = importlib.import_module("sqlalchemy")
    create_engine = sqlalchemy.create_engine
    text = sqlalchemy.text

    if not db_uri:
        raise ValueError("--db-uri is required for mimiciv-sql source")
    if not query_file:
        raise ValueError("--query-file is required for mimiciv-sql source")

    sql_path = Path(query_file)
    query = sql_path.read_text(encoding="utf-8")

    engine = create_engine(db_uri)
    with engine.connect() as conn:
        return pd.read_sql(text(query), conn)


def pick_series(df: pd.DataFrame, aliases: Iterable[str]) -> Optional[pd.Series]:
    lower_map = {c.lower(): c for c in df.columns}
    for alias in aliases:
        key = alias.lower()
        if key in lower_map:
            return df[lower_map[key]]
    return None


def to_numeric(s: Optional[pd.Series]) -> Optional[pd.Series]:
    if s is None:
        return None
    return pd.to_numeric(s, errors="coerce")


def to_datetime(s: Optional[pd.Series]) -> Optional[pd.Series]:
    if s is None:
        return None
    return s.apply(lambda v: dt_parser.parse(str(v)) if pd.notna(v) else pd.NaT)


def hash_id(raw_id: Any, salt: str) -> str:
    token = f"{salt}|{raw_id}".encode("utf-8")
    return hashlib.sha256(token).hexdigest()[:16]


def normalize_sex(s: Optional[pd.Series], n: int) -> pd.Series:
    if s is None:
        return pd.Series(["F"] * n)
    sx = s.astype(str).str.upper().str.strip()
    out = pd.Series(["F"] * n)
    out[sx.str.startswith("M", na=False)] = "M"
    out[sx.str.startswith("F", na=False)] = "F"
    return out


def derive_features(raw: pd.DataFrame, field_map: dict[str, list[str]], cfg: BuildConfig) -> pd.DataFrame:
    n = len(raw)

    case_id = pick_series(raw, field_map["case_id"])
    age = to_numeric(pick_series(raw, field_map["age"]))
    sex = normalize_sex(pick_series(raw, field_map["sex"]), n)
    weight = to_numeric(pick_series(raw, field_map["weight_kg"]))
    height = to_numeric(pick_series(raw, field_map["height_cm"]))
    bmi = to_numeric(pick_series(raw, field_map["bmi"]))

    dur = to_numeric(pick_series(raw, field_map["surgery_duration_min"]))
    if dur is None:
        start = to_datetime(pick_series(raw, field_map["surgery_start_time"]))
        end = to_datetime(pick_series(raw, field_map["surgery_end_time"]))
        if start is not None and end is not None:
            dur = (end - start).dt.total_seconds() / 60.0

    infusion = to_numeric(pick_series(raw, field_map["propofol_infusion_mg_per_min"]))
    if infusion is None:
        total_dose = to_numeric(pick_series(raw, field_map["propofol_total_dose_mg"]))
        if total_dose is not None and dur is not None:
            infusion = total_dose / dur.clip(lower=1)

    wake = to_numeric(pick_series(raw, field_map["observed_wake_delay_min"]))

    if bmi is None and weight is not None and height is not None:
        bmi = weight / (height.clip(lower=1) / 100.0) ** 2

    if height is None and weight is not None and bmi is not None:
        height = np.sqrt(weight / bmi.clip(lower=1e-6)) * 100

    lbm = None
    if weight is not None and bmi is not None:
        lbm = pd.Series(np.zeros(n))
        male = sex == "M"
        female = ~male
        lbm[male] = (9270.0 * weight[male]) / (6680.0 + 216.0 * bmi[male])
        lbm[female] = (9270.0 * weight[female]) / (8780.0 + 244.0 * bmi[female])

    required = {
        "Age": age,
        "WeightKg": weight,
        "BMI": bmi,
        "HeightCm": height,
        "LBM": lbm,
        "SurgeryDurationMin": dur,
        "InfusionRateMgPerMin": infusion,
    }
    missing = [k for k, v in required.items() if v is None]
    if missing:
        raise ValueError(f"Missing required fields after mapping: {', '.join(missing)}")

    if case_id is None:
        case_id = pd.Series(np.arange(1, n + 1))

    out = pd.DataFrame(
        {
            "PatientID": case_id.apply(lambda v: hash_id(v, cfg.deid_salt)),
            "Age": age,
            "Sex": sex,
            "WeightKg": weight,
            "BMI": bmi,
            "HeightCm": height,
            "LBM": lbm,
            "SurgeryDurationMin": dur,
            "InfusionRateMgPerMin": infusion,
        }
    )

    if wake is not None:
        out["ObservedWakeDelayMin"] = wake

    out = out.replace([np.inf, -np.inf], np.nan).dropna(subset=[
        "Age", "WeightKg", "BMI", "HeightCm", "LBM", "SurgeryDurationMin", "InfusionRateMgPerMin"
    ])

    out = out[(out["Age"] >= 18) & (out["Age"] <= 100)]
    out = out[(out["WeightKg"] >= 35) & (out["WeightKg"] <= 250)]
    out = out[(out["BMI"] >= 12) & (out["BMI"] <= 70)]
    out = out[(out["SurgeryDurationMin"] > 10) & (out["SurgeryDurationMin"] <= 24 * 60)]
    out = out[(out["InfusionRateMgPerMin"] > 0) & (out["InfusionRateMgPerMin"] <= 50)]

    if "ObservedWakeDelayMin" in out.columns:
        out = out[(out["ObservedWakeDelayMin"] >= 0) & (out["ObservedWakeDelayMin"] <= 180)]

    return out.reset_index(drop=True)


def main() -> None:
    args = parse_args()
    field_map = load_field_map(args.field_map)

    cfg = BuildConfig(
        deid_salt=args.deid_salt,
        drop_columns=["name", "dob", "mrn", "subject_id", "hadm_id", "stay_id"],
    )

    if args.source == "csv":
        if not args.input_csv:
            raise ValueError("--input-csv is required for source=csv")
        raw = pd.read_csv(args.input_csv)
    elif args.source == "vitaldb-api":
        raw = fetch_api_rows(args.api_url, args.api_token, args.api_timeout)
    elif args.source == "mimiciv-sql":
        raw = fetch_sql_rows(args.db_uri, args.query_file)
    else:
        raise ValueError(f"Unsupported source {args.source}")

    out = derive_features(raw, field_map, cfg)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out.to_csv(out_path, index=False)

    print(f"Wrote {len(out)} de-identified cases to: {out_path}")


if __name__ == "__main__":
    main()
