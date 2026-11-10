# Databricks notebook source
# 02_bronze_load: Auto Loader from ADLS bronze files -> nyctaxi.bronze.<table> (Delta).
# Rerunnable: the checkpoint remembers loaded files, so only new incremental folders are read.
# One-time setup (SQL): CREATE VOLUME IF NOT EXISTS nyctaxi.bronze.checkpoints;

# COMMAND ----------
from pyspark.sql import functions as F

def load_bronze(table: str):
    src = f"abfss://bronze@stnyctaxidev01.dfs.core.windows.net/nyctaxi/{table}/"
    chk = f"/Volumes/nyctaxi/bronze/checkpoints/{table}"

    df = (spark.readStream.format("cloudFiles")
          .option("cloudFiles.format", "parquet")
          .option("cloudFiles.schemaLocation", f"{chk}/_schema")
          .option("cloudFiles.partitionColumns", "")   # no year/month columns from folder names
          .option("pathGlobFilter", "*.parquet")
          .load(src)
          .withColumn("_source_file", F.col("_metadata.file_path"))
          .withColumn("_ingested_at", F.current_timestamp()))

    (df.writeStream
       .option("checkpointLocation", f"{chk}/_checkpoints")   # must match the folder created on first load
       .trigger(availableNow=True)          # batch-style: load all new files, then stop (serverless)
       .toTable(f"nyctaxi.bronze.{table}")
       .awaitTermination())

# COMMAND ----------
for t in ["green_trip", "yellow_trip"]:
    load_bronze(t)
    print(t, spark.table(f"nyctaxi.bronze.{t}").count())
