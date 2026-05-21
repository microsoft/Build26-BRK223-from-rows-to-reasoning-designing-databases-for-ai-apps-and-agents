-- Drop and recreate the product_sample table
-- Also drops the pipeline output table and recreates the auto-increment sequence

-- In Copilot
-- "create this table product-sample-table.sql with this data sample_data_products.csv"

-- Drop dependent objects first
DROP TABLE IF EXISTS product_rag_pipeline_output;
DROP TABLE IF EXISTS product_sample CASCADE;
DROP SEQUENCE IF EXISTS product_sample_id_seq;

-- Create the auto-increment sequence
CREATE SEQUENCE product_sample_id_seq START WITH 1;

-- Create the product_sample table
CREATE TABLE product_sample (
    id              integer DEFAULT nextval('product_sample_id_seq') NOT NULL,
    parent_asin     text,
    title           text,
    average_rating  real,
    rating_number   integer,
    features        jsonb,
    description     jsonb,
    price           numeric(10,2),
    images          jsonb,
    store           text,
    categories      jsonb,
    details         jsonb,
    embedding       vector(1536),
    price_num       numeric(10,2),
    category        text,
    content         text,
    CONSTRAINT products_pkey PRIMARY KEY (id)
);
