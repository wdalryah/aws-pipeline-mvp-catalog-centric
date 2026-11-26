-- semantic_orders.sql
-- CTAS query: joins bronze orders + customers + products to produce the gold semantic layer.
-- Partitioned by ingestion_date, written as Parquet/Snappy to gold/semantic_orders_summary/.
--
-- Template variables (substituted at runtime by the Glue driver or Airflow operator):
--   ${env}    - environment name, e.g. dev or prelive
--   ${bucket} - data lake S3 bucket name

CREATE TABLE gold_db_${env}.semantic_orders_summary
WITH (
    format             = 'PARQUET',
    write_compression  = 'SNAPPY',
    external_location  = 's3://${bucket}/gold/semantic_orders_summary/',
    partitioned_by     = ARRAY['ingestion_date'],
    table_type         = 'HIVE'
)
AS
SELECT
    -- Order dimensions
    o.order_id,
    o.order_date,

    -- Customer dimensions
    c.customer_id,
    c.name         AS customer_name,
    c.email        AS customer_email,
    c.country      AS customer_country,

    -- Product dimensions
    p.product_id,
    p.product_name,
    p.category     AS product_category,

    -- Financial metrics
    CAST(o.amount AS DOUBLE)                            AS order_amount,
    CAST(p.price  AS DOUBLE)                            AS list_price,
    CAST(o.amount AS DOUBLE) - CAST(p.price AS DOUBLE)  AS discount_amount,

    -- Audit columns (passed through from bronze orders as the driving table)
    o.pk_surrogate,
    o.source_system,
    o.source_file,
    o.ingestion_timestamp,
    o.env,
    o.region,
    o.job_run_id,
    o.is_deleted,
    o.record_hash,

    -- Partition column
    o.ingestion_date

FROM
    bronze_db_${env}.orders o
    INNER JOIN bronze_db_${env}.customers c
        ON o.customer_id = c.customer_id
    INNER JOIN bronze_db_${env}.products p
        ON o.product = p.product_name

WHERE
    o.is_deleted  = FALSE
    AND c.is_deleted = FALSE
    AND p.is_deleted = FALSE
;
