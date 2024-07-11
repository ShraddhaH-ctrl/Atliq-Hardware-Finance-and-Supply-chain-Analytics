-----  REPORT - 1   -----

SELECT s.date, s.product_code, p.product, p.variant, s.sold_quantity, g.gross_price,
       (g.gross_price*s.sold_quantity) AS gross_price_total
FROM fact_sales_monthly s JOIN dim_product p
ON 
   p.product_code = s.product_code
JOIN fact_gross_price g 
ON 
  g.product_code = s.product_code AND g.fiscal_year = get_fiscal_year(s.date)
WHERE customer_code = 90002002 AND get_fiscal_year(s.date)=2021 
LIMIT 1000000;


----- REPORT - 2 -----

SELECT s.date, SUM(s.sold_quantity * g.gross_price) AS gross_price_total
FROM fact_sales_monthly s  JOIN fact_gross_price g
ON 
  s.product_code = g.product_code AND g.fiscal_year = get_fiscal_year(s.date)
WHERE customer_code = 90002002
GROUP BY s.date
LIMIT 100000;


----- REPORT - 3 -----

SELECT SUM(sold_quantity) AS total_sold_quantity 
FROM fact_sales_monthly s JOIN dim_customer c 
ON s.customer_code = c.customer_code
WHERE get_fiscal_year(s.date) = 2021 AND market = "India"
GROUP BY market;


----- REPORT - 4 -----
-- STEP-1: Get the net_invoice_sales amount using the CTE's

SELECT     s.date, 
           s.fiscal_year,
           s.product_code, 
           c.market,
           p.product, 
           p.variant, 
           s.sold_quantity, 
           g.gross_price AS gross_price_per_item,
       ROUND(g.gross_price*s.sold_quantity, 2) AS gross_price_total,
	   pre.pre_invoice_discount_pct
FROM fact_sales_monthly s JOIN dim_product p
ON 
   s.product_code = p.product_code
JOIN dim_customer c 
ON
  s.customer_code = c.customer_code
JOIN fact_gross_price g 
ON 
g.fiscal_year = s.fiscal_year AND g.product_code = s.product_code 
JOIN fact_pre_invoice_deductions pre 
ON 
   pre.customer_code = s.customer_code AND pre.fiscal_year = s.fiscal_year
WHERE s.fiscal_year = 2021;


-- STEP-2: Creating the view `sales_preinv_discount`

SELECT     s.date, 
           s.fiscal_year,
           s.product_code,
           s.customer_code,
           c.market,
           p.product, 
           p.variant, 
           s.sold_quantity, 
           g.gross_price AS gross_price_per_item,
       ROUND(g.gross_price*s.sold_quantity, 2) AS gross_price_total,
	   pre.pre_invoice_discount_pct
FROM fact_sales_monthly s JOIN dim_product p
ON 
   s.product_code = p.product_code
JOIN dim_customer c 
ON
  s.customer_code = c.customer_code
JOIN fact_gross_price g 
ON 
g.fiscal_year = s.fiscal_year AND g.product_code = s.product_code 
JOIN fact_pre_invoice_deductions pre 
ON 
   pre.customer_code = s.customer_code AND pre.fiscal_year = s.fiscal_year;
   

-- STEP-3: Now generate 'net_invoice_sales' and 'post_invoice_discount_pct' using the above created view "sales_preinv_discount"

SELECT 
		s.date, s.fiscal_year,
		s.customer_code, s.market,
		s.product_code, s.product, s.variant, s.sold_quantity,
        s.gross_price_total, s.pre_invoice_discount_pct,
		(s.gross_price_total-s.pre_invoice_discount_pct*s.gross_price_total) as net_invoice_sales,
		(po.discounts_pct+po.other_deductions_pct) as post_invoice_discount_pct
FROM sales_preinv_discount s
JOIN fact_post_invoice_deductions po
ON po.customer_code = s.customer_code AND
po.product_code = s.product_code AND
po.date = s.date;

SELECT * FROM sales_postinv_discount;

-- STEP-4: Create a report for net sales
SELECT 
	*, 
	net_invoice_sales*(1-post_invoice_discount_pct) as net_sales
	FROM sales_postinv_discount;


-- STEP-5: Finally creating the view `net_sales` which inbuiltly use/include all the previous created view and gives the final result
SELECT * FROM net_sales;


-- STEP-6: Get top 5 market by net sales in fiscal year 2021
	SELECT 
    	    market, 
            round(sum(net_sales)/1000000,2) as net_sales_mln
	FROM net_sales
	where fiscal_year=2021
	group by market
	order by net_sales_mln desc
	limit 5;


----- REPORT-5 -----

WITH cte2 AS (
WITH cte1 AS (
SELECT 
	p.division,
    p.product,
    SUM(sold_quantity) AS total_sold_quantity
FROM net_sales s 
JOIN dim_product p 
ON 
  s.product_code=p.product_code
WHERE fiscal_year = 2021
GROUP BY p.division, p.product
) 
SELECT *, 
dense_rank() OVER(Partition by division Order by total_sold_quantity desc) AS drnk
FROM cte1
Order by division
)
SELECT * FROM cte2 
WHERE drnk < 4;


----- REPORT-6 -----

with forecast_err_table as (
             select
                  s.customer_code as customer_code,
                  c.customer as customer_name,
                  c.market as market,
                  sum(s.sold_quantity) as total_sold_qty,
                  sum(s.forecast_quantity) as total_forecast_qty,
                  sum(s.forecast_quantity-s.sold_quantity) as net_error,
                  round(sum(s.forecast_quantity-s.sold_quantity)*100/sum(s.forecast_quantity),1) as net_error_pct,
                  sum(abs(s.forecast_quantity-s.sold_quantity)) as abs_error,
                  round(sum(abs(s.forecast_quantity-sold_quantity))*100/sum(s.forecast_quantity),2) as abs_error_pct
             from fact_act_est s
             join dim_customer c
             on s.customer_code = c.customer_code
             where s.fiscal_year=2021
             group by customer_code
	)
	select 
            *,
            if (abs_error_pct > 100, 0, 100.0 - abs_error_pct) as forecast_accuracy
	from forecast_err_table
        order by forecast_accuracy desc;
