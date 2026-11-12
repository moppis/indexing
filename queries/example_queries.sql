SET NOCOUNT ON;

GO
/*
Heavy query examples for the heap tables created by init_scripts/init.sql.
Run these individually in indexlab; the latest-order lookup can be especially
expensive without indexes. Enable the actual execution plan in SSMS (Ctrl+M)
and compare logical reads and CPU time before and after adding indexes.
*/
SET STATISTICS IO ON;
SET STATISTICS TIME ON;

-- 1. Revenue by city and product category: four-table join, aggregation and sort.
SELECT   c.city,
         p.category,
         COUNT(DISTINCT o.order_id) AS OrderCount,
         SUM(CAST(oi.quantity AS BIGINT)) AS UnitsSold,
         SUM(oi.quantity * oi.unit_price) AS Revenue
FROM     dbo.customers AS c
         INNER JOIN dbo.orders AS o ON o.customer_id = c.customer_id
         INNER JOIN dbo.order_items AS oi ON oi.order_id = o.order_id
         INNER JOIN dbo.products AS p ON p.product_id = oi.product_id
WHERE    o.status = 'completed'
GROUP BY c.city, p.category
ORDER BY Revenue DESC, c.city, p.category;

-- 2. Top five customers per city, including ties: aggregate before ranking.
;WITH CustomerSpending AS (
    SELECT   c.customer_id,
             c.customer_name,
             c.city,
             COUNT_BIG(*) AS OrderCount,
             SUM(o.total_amount) AS TotalSpent,
             MAX(o.order_date) AS LastOrderDate
    FROM     dbo.customers AS c
             INNER JOIN dbo.orders AS o ON o.customer_id = c.customer_id
    WHERE    o.status = 'completed'
    GROUP BY c.customer_id, c.customer_name, c.city
),
RankedCustomers AS (
    SELECT *,
           DENSE_RANK() OVER (
               PARTITION BY city ORDER BY TotalSpent DESC
           ) AS CityRank
    FROM   CustomerSpending
)
SELECT   customer_id, customer_name, city, OrderCount,
         TotalSpent, LastOrderDate, CityRank
FROM     RankedCustomers
WHERE    CityRank <= 5
ORDER BY city, CityRank, customer_id;

-- 3. Monthly category revenue with running totals and month-over-month changes.
-- LAG compares months with sales; months without sales are not generated.
;WITH MonthlyRevenue AS (
    SELECT   p.category,
             DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS SalesMonth,
             SUM(oi.quantity * oi.unit_price) AS Revenue
    FROM     dbo.orders AS o
             INNER JOIN dbo.order_items AS oi ON oi.order_id = o.order_id
             INNER JOIN dbo.products AS p ON p.product_id = oi.product_id
    WHERE    o.status = 'completed'
    GROUP BY p.category,
             DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1)
)
SELECT   category,
         SalesMonth,
         Revenue,
         SUM(Revenue) OVER (
             PARTITION BY category ORDER BY SalesMonth
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
         ) AS RunningRevenue,
         Revenue - LAG(Revenue) OVER (
             PARTITION BY category ORDER BY SalesMonth
         ) AS RevenueChange
FROM     MonthlyRevenue
ORDER BY category, SalesMonth;

-- 4. Latest completed order for every customer, including those without one.
-- Without an index this can repeatedly scan and sort orders for each customer.
SELECT   c.customer_id,
         c.customer_name,
         c.city,
         latest.order_id,
         latest.order_date,
         latest.total_amount
FROM     dbo.customers AS c
         OUTER APPLY (
             SELECT TOP (1) o.order_id, o.order_date, o.total_amount
             FROM   dbo.orders AS o
             WHERE  o.customer_id = c.customer_id
                    AND o.status = 'completed'
             ORDER BY o.order_date DESC, o.order_id DESC
         ) AS latest
ORDER BY c.customer_id;

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

-- copy table if you want to compare the original vs an indexed version
INSERT INTO customers
    FROM customers;

/* 
List all available pages for our tables. 
When creating indexes old pages are replaced with new ones. 
Make sure to run this again to get the new ids
(db, table, index id (-1 = all))
*/
DBCC IND ('indexlab', 'customers', -1);

-- Read page headers, get id info from DBCC IND
-- (db id, file id, page id, mode (DETAILED or LIMITED))
SELECT *
FROM   sys.dm_db_page_info(DB_ID('indexlab'), 1, 408, 'DETAILED');

/*
Page dump, includes data rows. 
We need to set the trace flag once before we can run dbcc page
(db, file id, page id, print option (3 = everything))
*/
DBCC TRACEON (3604);


GO
DBCC PAGE ('indexlab', 1, 552, 3);

-- Create a clustered index, this will rearrange the data in the data pages
CREATE CLUSTERED INDEX idx_customers_customer_id
    ON dbo.customers(customer_id);

-- if you need to drop the index
DROP INDEX idx_customers_customer_id
    ON dbo.customers;

-- Create a non-clustered index
CREATE INDEX idx_customers_first_name
    ON dbo.customers(firstname);

/*
Create a non-clustered composite index. By adding DESC we are telling the db to sort the index in descending order instead of the default asc
Remember that when creating a composite index the order matter!
*/
CREATE INDEX idx_customers_firstname_lastname
    ON dbo.customers(firstname DESC, lastname);

/*
Create a non-clustered composite index that includes email as a non-key into the index page.
Now depending on the query we might not need to access the data page to retrive the email value we can take it directly from the index page.
*/
CREATE INDEX idx_customers_firstname_lastname_including_email
    ON dbo.customers(firstname DESC, lastname)
    INCLUDE(email);

/*
By adding EXPLAIN in front of your query you can view the estimated execution plan (the query is not executed)
By adding EXPLAIN ANALYSE in front of your query you can study the actual execution plan (the query is executed)

TIP: if running ssms you can press ctrl+l for the estimated plan and ctrl+m for the actual
*/
/*
By querying sys.dm_db_index_usage_stats we can get usage statistics on our indexes
*/
SELECT   tbl.name AS TableName,
         idx.type_desc AS IndexType,
         idx.is_primary_key AS IsPrimaryKey,
         idx.is_unique AS IsUnique,
         idx.is_disabled AS IsDisabled,
         s.user_seeks AS UserSeeks,
         s.user_scans AS UserScans,
         s.user_lookups AS UserLookups,
         s.user_updates AS UserUpdates,
         COALESCE (s.last_user_seek, s.last_user_scan) AS LastUsed
FROM     sys.indexes AS idx
         INNER JOIN
         sys.tables AS tbl
         ON idx.object_id = tbl.object_id
         LEFT OUTER JOIN
         sys.dm_db_index_usage_stats AS s
         ON s.object_id = idx.object_id
            AND s.index_id = idx.index_id
ORDER BY tbl.name,
         idx.name;

/*
sys.dm_db_missing_index_details can give us recommended indexes we can add in case we have missed something.
Important TIP! do not just add the recommendations, evaluate first!
*/
SELECT *
FROM   sys.dm_db_missing_index_details;

/*
With this query we can see if we have dublicated indexes, by checking which columns are used in the indexes
*/
SELECT   tbl.name AS TableName,
         col.name AS IndexColumn,
         idx.name AS IndexName,
         idx.type_desc AS IndexType,
         COUNT(*) OVER (PARTITION BY tbl.name,
                                     col.name) AS ColumnCount
FROM     sys.indexes AS idx
         INNER JOIN
         sys.tables AS tbl
         ON idx.object_id = tbl.object_id
         INNER JOIN
         sys.index_columns AS ic
         ON idx.object_id = ic.object_id
            AND idx.index_id = ic.index_id
         INNER JOIN
         sys.columns AS col
         ON ic.object_id = col.object_id
            AND ic.column_id = col.column_id
ORDER BY ColumnCount DESC;

/*
After a while a index might become framented, meaning there could be gaps in the pages or they are out of order.
The following query tells us how fragmented they are
*/
SELECT   tbl.name AS TableName,
         idx.name AS IndexName,
         s.avg_fragmentation_in_percent,
         s.page_count,
         RecommendedAction = CASE WHEN s.avg_fragmentation_in_percent < 10 THEN 'NO ACTION NEEDED' WHEN s.avg_fragmentation_in_percent < 30 THEN 'REORGANIZE' ELSE 'REBUILD' END
FROM     sys.dm_db_index_physical_stats(DB_ID('indexlab'), NULL, NULL, NULL, 'LIMITED') AS s
         INNER JOIN
         sys.tables AS tbl
         ON s.object_id = tbl.object_id
         INNER JOIN
         sys.indexes AS idx
         ON idx.object_id = s.object_id
            AND s.index_id = idx.index_id
ORDER BY s.avg_fragmentation_in_percent DESC;

/*
reorganize - defragment leaf nodes to keep them sorted (light operation)
*/
ALTER INDEX idx_customers_customer_id
    ON customers REORGANIZE;

/*
rebuild - drops index and rebuilds it (heavy operation)
*/
ALTER INDEX idx_customers_customer_id
    ON customers REBUILD;

/*
These are not yet adapted to the tables in this example, they are simply taken from the sql server docs just to showcase the process.
Feel free to try it out.
*/
CREATE PARTITION FUNCTION myRangePF1(DATETIME2 (0))
    AS RANGE RIGHT
    FOR VALUES ('2022-04-01', '2022-05-01', '2022-06-01');


GO
CREATE PARTITION SCHEME myRangePS1
    AS PARTITION myRangePF1
    ALL TO ('PRIMARY');


GO
CREATE TABLE dbo.PartitionTable (
    col1 DATETIME2 (0) PRIMARY KEY,
    col2 CHAR (10)    
) ON myRangePS1 (col1);


GO