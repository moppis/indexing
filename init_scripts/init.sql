CREATE DATABASE indexlab;
GO
USE indexlab;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

CREATE TABLE dbo.customers (
    customer_id INT NOT NULL,
    email VARCHAR(100) NOT NULL,
    city VARCHAR(40) NOT NULL,
    customer_name VARCHAR(80) NOT NULL
);
CREATE TABLE dbo.products (
    product_id INT NOT NULL,
    category VARCHAR(30) NOT NULL,
    product_name VARCHAR(80) NOT NULL,
    price DECIMAL(12,2) NOT NULL
);
CREATE TABLE dbo.orders (
    order_id INT NOT NULL,
    customer_id INT NOT NULL,
    order_date DATE NOT NULL,
    status VARCHAR(20) NOT NULL,
    total_amount DECIMAL(12,2) NOT NULL
);
CREATE TABLE dbo.order_items (
    order_item_id INT NOT NULL,
    order_id INT NOT NULL,
    product_id INT NOT NULL,
    quantity INT NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL
);

BULK INSERT dbo.customers FROM '/data/customers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT dbo.products FROM '/data/products.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT dbo.orders FROM '/data/orders.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK);
BULK INSERT dbo.order_items FROM '/data/order_items.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0a', TABLOCK);

COMMIT;

UPDATE STATISTICS dbo.customers WITH FULLSCAN;
UPDATE STATISTICS dbo.products WITH FULLSCAN;
UPDATE STATISTICS dbo.orders WITH FULLSCAN;
UPDATE STATISTICS dbo.order_items WITH FULLSCAN;
