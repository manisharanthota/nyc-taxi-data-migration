# Databricks notebook source
# 02_silver_load: bronze -> silver (incremental).
# Per run: stream new bronze rows (checkpoint = watermark) -> transform_trips -> MERGE silver,
# MERGE quarantine, flag reversal pairs. Rerunnable: reruns insert nothing.
# One-time setup (SQL): run 01_silver_tables; CREATE VOLUME IF NOT EXISTS nyctaxi.silver.checkpoints;

# COMMAND ----------
from pyspark.sql import functions as F, Window

def transform_trips(df, taxi_type):
    """Bronze rows -> (silver_df, quarantine_df)."""
    # A: dedupe (reruns / orphan partial files) - keep latest copy per trip_id
    w = Window.partitionBy("trip_id").orderBy(F.col("_ingested_at").desc())
    df = df.withColumn("rn", F.row_number().over(w)).filter("rn = 1").drop("rn")

    # B: quarantine reason (impossible rows)
    dur_sec = F.col("dropoff_datetime").cast("long") - F.col("pickup_datetime").cast("long")
    max_date = F.add_months(F.trunc(F.current_date(), "MM"), 1)
    df = df.withColumn("reason",
        F.when(F.col("pickup_datetime") < "2024-01-01", "OUT_OF_RANGE_DATE")
         .when(F.col("pickup_datetime") >= max_date, "OUT_OF_RANGE_DATE")
         .when(dur_sec < 0, "DROPOFF_BEFORE_PICKUP")
         .when(dur_sec == 0, "ZERO_DURATION")
         .when(dur_sec > 86400, "DURATION_GT_24H")
         .when(F.col("total_amount") > 1000, "FARE_GT_1000"))

    bad = df.filter("reason IS NOT NULL")
    quarantine_df = bad.select(
        F.lit(taxi_type).alias("taxi_type"), "trip_id", "reason", "pickup_datetime",
        F.to_json(F.struct(*[c for c in bad.columns if c != "reason"])).alias("raw_record"),
        "_source_file", F.current_timestamp().alias("_quarantined_at"))

    # C: NULL out fake values (row kept)
    df = df.filter("reason IS NULL").drop("reason")
    mph = F.col("trip_distance") / (dur_sec / 3600)
    bad_distance = ((F.col("trip_distance") <= 0) | (F.col("trip_distance") > 100) |
                    (mph > 100) | ((F.col("trip_distance") > 5) & (dur_sec < 60)))
    df = (df
        .withColumn("trip_distance",   F.when(bad_distance, None).otherwise(F.col("trip_distance")))
        .withColumn("passenger_count", F.when(F.col("passenger_count") == 0, None).otherwise(F.col("passenger_count")))
        .withColumn("rate_code_id",    F.when(F.col("rate_code_id") == 99, None).otherwise(F.col("rate_code_id"))))

    # D: flags, derived, lineage, final shape
    df = (df
        .withColumn("pricing_type",
            F.when((F.col("payment_type_id") == 0) | F.col("payment_type_id").isNull(), "FLEX").otherwise("METERED"))
        .withColumn("is_adjustment", F.col("total_amount") < 0)
        .withColumn("is_reversal", F.lit(False))          # set by flag_reversals after MERGE
        .withColumn("pickup_date", F.to_date("pickup_datetime"))
        .withColumn("trip_duration_min", (dur_sec / 60).cast("decimal(10,2)"))
        .withColumnRenamed("created_at", "source_created_at")
        .withColumn("_silver_updated_at", F.current_timestamp()))
    target_cols = df.sparkSession.table(f"nyctaxi.silver.{taxi_type}_trip").columns
    silver_df = df.select(*target_cols)

    return silver_df, quarantine_df

# COMMAND ----------
def merge_silver(silver_df, taxi_type):
    silver_df.createOrReplaceTempView("src")
    silver_df.sparkSession.sql(f"""
        MERGE INTO nyctaxi.silver.{taxi_type}_trip AS tgt
        USING src
          ON tgt.trip_id = src.trip_id
        WHEN MATCHED AND src._ingested_at > tgt._ingested_at THEN UPDATE SET *
        WHEN NOT MATCHED THEN INSERT *
    """)

def merge_quarantine(quarantine_df):
    quarantine_df.createOrReplaceTempView("q_src")
    quarantine_df.sparkSession.sql("""
        MERGE INTO nyctaxi.silver.trip_quarantine AS tgt
        USING q_src AS src
          ON tgt.taxi_type = src.taxi_type AND tgt.trip_id = src.trip_id
        WHEN NOT MATCHED THEN INSERT *
    """)

def flag_reversals(dates_df, taxi_type):
    """Flag both halves of mirror pairs (+X / -X), only for pickup dates in dates_df."""
    dates_df.select("pickup_date").distinct().createOrReplaceTempView("batch_dates")
    dates_df.sparkSession.sql(f"""
        MERGE INTO nyctaxi.silver.{taxi_type}_trip AS tgt
        USING (
            SELECT DISTINCT a.trip_id, a.pickup_date
            FROM nyctaxi.silver.{taxi_type}_trip a
            JOIN nyctaxi.silver.{taxi_type}_trip b
              ON  a.vendor_id        = b.vendor_id
              AND a.pickup_datetime  = b.pickup_datetime
              AND a.dropoff_datetime = b.dropoff_datetime
              AND a.pu_location_id   = b.pu_location_id
              AND a.do_location_id   = b.do_location_id
              AND a.total_amount     = -b.total_amount
              AND a.trip_id         <> b.trip_id
            WHERE a.total_amount <> 0
              AND a.pickup_date IN (SELECT pickup_date FROM batch_dates)
              AND b.pickup_date IN (SELECT pickup_date FROM batch_dates)
        ) src
        ON tgt.trip_id = src.trip_id AND tgt.pickup_date = src.pickup_date
        WHEN MATCHED AND tgt.is_reversal = false THEN
          UPDATE SET is_reversal = true, _silver_updated_at = current_timestamp()
    """)

# COMMAND ----------
def load_silver(taxi_type):
    chk = f"/Volumes/nyctaxi/silver/checkpoints/{taxi_type}_trip"

    def process_batch(batch_df, batch_id):
        s, q = transform_trips(batch_df, taxi_type)
        merge_silver(s, taxi_type)
        merge_quarantine(q)
        flag_reversals(s, taxi_type)

    (spark.readStream.option("skipChangeCommits", "true")
      .table(f"nyctaxi.bronze.{taxi_type}_trip")
        .writeStream
        .foreachBatch(process_batch)
        .option("checkpointLocation", chk)
        .trigger(availableNow=True)
        .start()
        .awaitTermination())

# COMMAND ----------
# One-time backfill of is_reversal (only needed if silver was loaded before flag_reversals existed):
# for t in ["green", "yellow"]:
#     flag_reversals(spark.table(f"nyctaxi.silver.{t}_trip"), t)

# COMMAND ----------
for t in ["green", "yellow"]:
    load_silver(t)
    print(t, spark.table(f"nyctaxi.silver.{t}_trip").count())
