--counting rows per month and year for yellow taxi trips
SELECT YEAR(pickup_datetime) AS yr,MONTH(pickup_datetime) AS mth,count(*) AS total_rows
FROM trips.yellow_trip
GROUP BY YEAR(pickup_datetime),MONTH(pickup_datetime)
ORDER BY YEAR(pickup_datetime),MONTH(pickup_datetime);