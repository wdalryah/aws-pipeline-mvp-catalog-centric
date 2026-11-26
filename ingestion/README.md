# ingestion/

Reserved for ingestion engine configuration.

Planned contents:
- `dms/` — AWS DMS replication instance and task configs (Terraform)
- `table_mapping/` — DMS table mapping JSON files per source (finance domain: customers, orders, products)
- `connectors/` — Source connection definitions

## Current assumption

Tables are assumed to be pre-landed in the S3 raw/landing zone:

```
s3://datalake-medallion-prelive-eu-north-1/raw/landing/customers/
s3://datalake-medallion-prelive-eu-north-1/raw/landing/orders/
s3://datalake-medallion-prelive-eu-north-1/raw/landing/products/
```

Processing picks up from there. Ingestion configuration will be added in a future iteration.
