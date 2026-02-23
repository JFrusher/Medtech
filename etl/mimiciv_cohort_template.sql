-- MIMIC-IV cohort template query (adapt to your local schema and access model)
-- Goal: export one row per anesthesia case with columns mappable by
-- etl/build_deidentified_cohort.py

SELECT
    p.subject_id AS subject_id,
    p.anchor_age AS anchor_age,
    p.gender AS gender,
    c.weight_kg AS weight_kg,
    c.height_cm AS height_cm,
    c.bmi AS bmi,
    c.surgery_duration_min AS surgery_duration_min,
    c.propofol_infusion_mg_per_min AS propofol_infusion_mg_per_min,
    c.observed_wake_delay_min AS observed_wake_delay_min
FROM your_derived_anesthesia_cohort c
JOIN mimiciv_hosp.patients p
  ON c.subject_id = p.subject_id
WHERE c.surgery_duration_min IS NOT NULL
  AND c.propofol_infusion_mg_per_min IS NOT NULL;
