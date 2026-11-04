WITH ct AS (
  SELECT table_name, year_month, row_count
  FROM audit.control_totals
  WHERE captured_at = (SELECT MAX(captured_at) FROM audit.control_totals)
), lg AS (
  SELECT table_name, year_month, rows_read, rows_copied,
         ROW_NUMBER() OVER (PARTITION BY table_name, year_month ORDER BY log_id DESC) AS rn
  FROM etl.adf_load_log
  WHERE status = 'success'
)
SELECT ct.table_name, ct.year_month, ct.row_count, lg.rows_read, lg.rows_copied,
       CASE WHEN lg.rows_copied IS NULL THEN 'NOT LOADED'
            WHEN lg.rows_copied = ct.row_count AND lg.rows_read = ct.row_count THEN 'OK'
            ELSE 'MISMATCH' END AS check_status
FROM ct
LEFT JOIN lg ON lg.table_name = ct.table_name AND lg.year_month = ct.year_month AND lg.rn = 1
ORDER BY check_status DESC, ct.table_name, ct.year_month;