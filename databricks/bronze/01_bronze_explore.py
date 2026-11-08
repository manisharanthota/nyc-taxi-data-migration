# Databricks notebook source
# 01_bronze_explore: look at what ADF landed in ADLS before building bronze tables.

# COMMAND ----------
base = "abfss://bronze@stnyctaxidev01.dfs.core.windows.net/nyctaxi/"
display(dbutils.fs.ls(base))

# COMMAND ----------
# Drill into one table: month folders + incremental folder
display(dbutils.fs.ls(f"{base}yellow_trip/"))
display(dbutils.fs.ls(f"{base}yellow_trip/incremental/"))

# COMMAND ----------
# Read ONE month file (not the whole table folder: mixed year=/month= and incremental/load_id= layouts)
month_path = f"{base}yellow_trip/year=2025/month=02/"
df = spark.read.parquet(month_path)
df.printSchema()
print(df.count())   # compare with etl.adf_load_log rows_copied for that month
display(df.limit(10))

# COMMAND ----------
# Check an incremental file has the same schema as the month file
# incr_path = f"{base}yellow_trip/incremental/load_id=<runId>/"
# spark.read.parquet(incr_path).printSchema()
