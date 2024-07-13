-- Storing items that are not moving, candidate for removal from the product line.
-- Are inventory numbers related to sales figures.
-- Where are the items stored and if they rearranged, could a warehouse be eliminated?

-- #1. Create duplicates of table to avoid data loss from the raw data
CREATE table customers_data_cleaning like customers;
create table employees_data_cleaning like employees;
create table offices_data_cleaning like offices;
create table orderdetails_data_cleaning like orderdetails;
create table orders_data_cleaning like orders;
create table payments_data_cleaning like payments;
create table productlines_data_cleaning like productlines;
create table products_data_cleaning like products;
create table warehouses_data_cleaning like warehouses;

-- #2. Insert table data into new tables
Insert into customers_data_cleaning Select * from customers;
Insert into employees_data_cleaning Select * from employees;
Insert into offices_data_cleaning Select * from offices;
Insert into orderdetails_data_cleaning Select * from orderdetails;
Insert into orders_data_cleaning Select * from orders;
Insert into payments_data_cleaning Select * from payments;
Insert into productlines_data_cleaning Select * from productlines;
Insert into products_data_cleaning Select * from products;
Insert into warehouses_data_cleaning Select * from warehouses;


-- After the data acquisition and data cleaning of this data set.

-- 1.Identification of the quantity of items for each product line 
-- in the products_data_cleaning table and their corresponding storage locations.

select productLine,warehouseCode, 
		count(productline) items
from products_data_cleaning
group by productline,warehouseCode 
order by 2;

-- 1.1 Total Quantity In Stock by Productline
select ProductLine,WarehouseCode,sum(QuantityInStock)
from products_data_cleaning
group by productLine;


-- 2. Creation of a table named "total_orders" 
-- to compute the overall product orders from the order details table.

CREATE TABLE total_orders
select * from
(
Select productCode,sum(quantityOrdered) Demand
from orderdetails_data_cleaning
group by productCode
) as tot;

select * from total_orders;

-- 2.1 Calculate the total quantity ordered by productline

select prod.ProductLine,prod.WarehouseCode,
sum(tot.Demand) QuantityOrderedByProductline
from (products_data_cleaning as prod
right join total_orders as tot
	on prod.productCode = tot.productCode)
group by prod.Productline,prod.WarehouseCode
order by 3 DESC;

-- 2.2 Then query a SQL SELECT statement to show the frequency 
-- of orders for each item using the count aggregate function.

select productcode, count(productcode)
from orderdetails_data_cleaning
group by productCode;

-- 2.3 Determine the lead times for each order from the orders_data_cleaning table using the datediff function.
  SELECT
	cust.CustomerNumber,cust.CustomerName,
    o.Ordernumber,o.Orderdate,o.ShippedDate,
	datediff(o.ShippedDate,o.orderDate) LeadTimes
    FROM 
	customers_data_cleaning cust
	INNER JOIN orders_data_cleaning o 
		ON cust.customerNumber = o.customerNumber
	WHERE shippedDate IS NOT NULL
	ORDER BY 3; 


-- 3. Utilization of Common Table Expressions (CTE) to calculate the quantity in stock
-- and the total amount ordered by joining the products and total_orders table.
-- Subsequently, another CTE was created to determine the percentage
--  of remaining stock for each product, followed by 
-- the use of a further CTE to categorize the percentage of stock remaining using a case statement.

WITH CTE_Quantity_Sold AS
(
select prod.ProductCode,prod.ProductName,prod.Productline,
		prod.WarehouseCode,prod.QuantityInstock,
		Demand
from(
	products_data_cleaning as prod
	right join total_orders as tot
		on prod.productCode = tot.productCode
	)
group by prod.ProductCode,prod.ProductName,prod.Productline,
		prod.WarehouseCode,prod.QuantityInstock,
       demand
order by 4
),
CTE_Quantity_Vs_Orders AS
(
SELECT *,
(QuantityInstock-Demand) StocksLeft
FROM CTE_Quantity_Sold
),
CTE_Quantity_Vs_Orders1 AS
(
SELECT *,
concat(round((100-Demand/QuantityInStock*100)),'%') PercentageOfStockLeft
FROM CTE_Quantity_Vs_Orders
),
CTE_Quantity_Vs_Orders2 AS
(
SELECT *,
CASE 
	WHEN PercentageOfStockLeft < 0 THEN "Unserved Demand"
    WHEN PercentageOfStockLeft <=25 THEN "Reflenish Stock"
    WHEN PercentageOfStockLeft <= 50 THEN "Check Availability"
	WHEN PercentageOfStockLeft between 51 AND 80 THEN "Needs an Item Review"
    WHEN PercentageOfStockLeft >=81 THEN "SLOW MOVING ITEM"
END as Remarks
FROM CTE_Quantity_Vs_Orders1
 )
 SELECT * -- sum(stocksleft) NotServed -- uncomment the aggregate function sum to calculate the total unserved items
FROM CTE_Quantity_Vs_Orders2
-- where percentageOfstockleft < 0 -- uncomment this where clause to perform the aggregate function sum
-- where remarks = 'slow moving item' and percentageOfstockleft >= 90 
-- and productline = 'ships' -- like 'trucks%' -- or 'planes') -- 'motorcycles''vintage cars''trains''ships''trucks%')
-- where productname like '%fer%'
order by 4,7 ;


-- 4. Generation of a product sales table to compute the sales amount per product 
-- based on the order date by year and month by joining three tables( orderdetails,orders,products).
-- This was followed by executing a query on the product sales table to summarize the total sales amount 
-- ordered by the product and determine the corresponding percentile rank using the percentile rank function.

CREATE table ProductSales
SELECT prod.productCode,prod.productName,prod.productLine,
	SUBSTRING(o.orderDate,1,7) AS `MONTH`,
    (det.quantityOrdered * det.priceEach) OrderAmount
FROM orderDetails_data_cleaning det
	INNER JOIN orders_data_cleaning o 
    ON det.orderNumber = o.orderNumber
	INNER JOIN products_data_cleaning prod
    ON prod.productCode = det.productCode
GROUP BY prod.productCode,prod.productName,prod.productLine,`Month`,OrderAmount;
    
SELECT * FROM ProductSales;
    
SELECT ProductName,productLine,`Month`,orderAmount,
    ROUND(PERCENT_RANK()OVER (PARTITION BY `Month`
        ORDER BY orderAmount),2) PercentileRank
FROM productSales
where month = '2003-01'
ORDER BY 3;
    
SELECT productCode,productname,productline, sum(orderamount) TotalOrderedSales
FROM productSales
GROUP BY productCode,productname,productline
ORDER BY 4 DESC;
    
-- Sum of Quantity Ordered based on Productline
select prod.ProductLine,prod.WarehouseCode,
sum(tot.Demand) QuantityOrderedByProductline
from (products_data_cleaning as prod
right join total_orders as tot
	on prod.productCode = tot.productCode)
group by prod.Productline,prod.WarehouseCode
order by 3 DESC;


-- 4.1 Create a CTE "CTE_SalesRank" and use the percent_rank window function 
-- to determine the percentile rank of each product line based on sales.

WITH CTE_SalesRank AS (
    SELECT ProductLine,
		SUM(orderAmount) OrderAmount
    FROM productSales
    GROUP BY productLine
)
SELECT ProductLine,OrderAmount,
    ROUND (PERCENT_RANK() OVER (ORDER BY orderAmount),2) PercentileRank
FROM CTE_SalesRank;


-- 5. Comparison of the total ordered amount to the total payment received

    
    select sum(orderamount) OverallOrderedAmount
    from productsales;
    
    select sum(amount) OverallPaymentsRecieved
    from payments_data_cleaning;
   
   -- / does not match because some of the orders are not served due to lack of availability of the items 
   
   -- End EDA